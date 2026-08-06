import AVFoundation
import ArrangerLabCore
import Foundation

final class AudioEvidenceWritePipeline: @unchecked Sendable {
    private final class SendableBuffer: @unchecked Sendable {
        let value: AVAudioPCMBuffer

        init(_ value: AVAudioPCMBuffer) {
            self.value = value
        }
    }

    private final class ConverterInputProvider: @unchecked Sendable {
        private let buffer: AVAudioPCMBuffer
        private var suppliedInput = false

        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func next(
            status: UnsafeMutablePointer<AVAudioConverterInputStatus>
        ) -> AVAudioBuffer? {
            if suppliedInput {
                status.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            status.pointee = .haveData
            return buffer
        }
    }

    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let workQueue = DispatchQueue(
        label: "ArrangerLab.AudioEvidenceWritePipeline",
        qos: .userInitiated
    )
    private let availableSlots: DispatchSemaphore
    private let state = NSCondition()
    private var acceptingInput = true
    private var activeSubmissions = 0
    private var firstError: Error?
    private var writer: ((AVAudioPCMBuffer) throws -> Void)?
    private var samples: [Float] = []

    init?(
        sourceFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        maximumPendingBuffers: Int = 32,
        writer: @escaping (AVAudioPCMBuffer) throws -> Void
    ) {
        guard maximumPendingBuffers > 0,
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }
        self.targetFormat = targetFormat
        self.converter = converter
        availableSlots = DispatchSemaphore(value: maximumPendingBuffers)
        self.writer = writer
    }

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard beginSubmission() else { return }
        defer { endSubmission() }

        guard availableSlots.wait(timeout: .now()) == .success else {
            retain(
                ArrangerLabError.corruptCapture(
                    "audio evidence pipeline could not keep up with input"
                )
            )
            return
        }
        guard let copiedBuffer = buffer.copy() as? AVAudioPCMBuffer else {
            availableSlots.signal()
            retain(
                ArrangerLabError.corruptCapture(
                    "audio input buffer could not be copied"
                )
            )
            return
        }

        let sendableBuffer = SendableBuffer(copiedBuffer)
        workQueue.async { [self, sendableBuffer] in
            defer { availableSlots.signal() }
            guard retainedError() == nil else { return }
            do {
                try convertWriteAndCollect(sendableBuffer.value)
            } catch {
                retain(error)
            }
        }
    }

    func finish() throws -> [Float] {
        closeAndWaitForSubmissions()
        let completedSamples = workQueue.sync {
            let completedSamples = samples
            samples.removeAll(keepingCapacity: false)
            writer = nil
            return completedSamples
        }
        if let error = retainedError() {
            throw error
        }
        return completedSamples
    }

    func cancelAndDrain() {
        closeAndWaitForSubmissions()
        workQueue.sync {
            samples.removeAll(keepingCapacity: false)
            writer = nil
        }
    }

    private func beginSubmission() -> Bool {
        state.lock()
        defer { state.unlock() }
        guard acceptingInput, firstError == nil else { return false }
        activeSubmissions += 1
        return true
    }

    private func endSubmission() {
        state.lock()
        activeSubmissions -= 1
        if activeSubmissions == 0 {
            state.broadcast()
        }
        state.unlock()
    }

    private func closeAndWaitForSubmissions() {
        state.lock()
        acceptingInput = false
        while activeSubmissions > 0 {
            state.wait()
        }
        state.unlock()
    }

    private func retain(_ error: Error) {
        state.lock()
        if firstError == nil {
            firstError = error
        }
        acceptingInput = false
        state.broadcast()
        state.unlock()
    }

    private func retainedError() -> Error? {
        state.lock()
        defer { state.unlock() }
        return firstError
    }

    private func convertWriteAndCollect(_ input: AVAudioPCMBuffer) throws {
        let rateRatio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * rateRatio)) + 1
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            throw ArrangerLabError.corruptCapture(
                "audio conversion buffer could not be allocated"
            )
        }

        let inputProvider = ConverterInputProvider(input)
        var conversionError: NSError?
        let conversionStatus = converter.convert(
            to: converted,
            error: &conversionError
        ) { _, inputStatus in
            inputProvider.next(status: inputStatus)
        }
        if let conversionError {
            throw conversionError
        }
        guard conversionStatus != .error,
              let channel = converted.floatChannelData?[0] else {
            throw ArrangerLabError.corruptCapture("audio input conversion failed")
        }
        guard let writer else {
            throw ArrangerLabError.corruptCapture(
                "audio evidence writer closed before pending work completed"
            )
        }

        try writer(converted)
        samples.append(
            contentsOf: UnsafeBufferPointer(
                start: channel,
                count: Int(converted.frameLength)
            )
        )
    }
}

public final class AudioEvidenceRecorder {
    private let engine = AVAudioEngine()
    private var pipeline: AudioEvidenceWritePipeline?
    private var startedAt: Date?
    private var targetURL: URL?
    private var tapInstalled = false

    public init() {}

    init(
        pipeline: AudioEvidenceWritePipeline,
        targetURL: URL,
        startedAt: Date
    ) {
        self.pipeline = pipeline
        self.targetURL = targetURL
        self.startedAt = startedAt
    }

    public func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }

    public func start(to url: URL) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw ArrangerLabError.microphoneDenied }
        stopSilently()
        let input = engine.inputNode
        let sourceFormat = input.inputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount >= 1,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false) else {
            throw ArrangerLabError.unsupported("audio input cannot be converted to mono 48 kHz")
        }
        let outputFile = try AVAudioFile(forWriting: url, settings: targetFormat.settings)
        guard let recordingPipeline = AudioEvidenceWritePipeline(
            sourceFormat: sourceFormat,
            targetFormat: targetFormat,
            writer: { buffer in
                try outputFile.write(from: buffer)
            }
        ) else {
            throw ArrangerLabError.unsupported(
                "audio input cannot be converted to mono 48 kHz"
            )
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: sourceFormat) { buffer, _ in
            recordingPipeline.enqueue(buffer)
        }
        tapInstalled = true
        pipeline = recordingPipeline
        targetURL = url
        startedAt = Date()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopSilently()
            throw error
        }
    }

    public func stop() throws -> AudioEvidenceRecord {
        guard let url = targetURL,
              let start = startedAt,
              let recordingPipeline = pipeline else {
            throw ArrangerLabError.invalidValue("audio recorder is not running")
        }
        stopInput()
        let duration = Date().timeIntervalSince(start)
        defer {
            pipeline = nil
            targetURL = nil
            startedAt = nil
        }
        let samples = try recordingPipeline.finish()
        let metrics = AudioAnalyzer.analyze(samples: samples, sampleRate: 48_000)
        return .init(id: UUID(), relativePath: "audio/\(url.lastPathComponent)", sampleRate: 48_000, channels: 1, durationSeconds: duration, metrics: metrics)
    }

    public func stopSilently() {
        stopInput()
        pipeline?.cancelAndDrain()
        pipeline = nil
        targetURL = nil
        startedAt = nil
    }

    private func stopInput() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
    }
}

public enum AudioFileAnalyzer {
    public static func evidence(for url: URL, preserving record: AudioEvidenceRecord) throws -> AudioEvidenceRecord {
        let file = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            throw ArrangerLabError.corruptCapture("cannot allocate audio buffer for \(url.lastPathComponent)")
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else {
            throw ArrangerLabError.corruptCapture("audio is not float PCM: \(url.lastPathComponent)")
        }
        let count = Int(buffer.frameLength)
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<Int(buffer.format.channelCount) {
            for index in 0..<count { mono[index] += channels[channel][index] }
        }
        if buffer.format.channelCount > 1 {
            let divisor = Float(buffer.format.channelCount)
            for index in mono.indices { mono[index] /= divisor }
        }
        let sampleRate = buffer.format.sampleRate
        return .init(
            id: record.id,
            relativePath: record.relativePath,
            sampleRate: sampleRate,
            channels: 1,
            durationSeconds: Double(count) / sampleRate,
            metrics: AudioAnalyzer.analyze(samples: mono, sampleRate: sampleRate)
        )
    }
}
