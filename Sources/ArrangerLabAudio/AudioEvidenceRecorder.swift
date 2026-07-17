import AVFoundation
import ArrangerLabCore
import Foundation

public final class AudioEvidenceRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var samples: [Float] = []
    private var startedAt: Date?
    private var targetURL: URL?

    public init() {}

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
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw ArrangerLabError.unsupported("audio input cannot be converted to mono 48 kHz")
        }
        let outputFile = try AVAudioFile(forWriting: url, settings: targetFormat.settings)
        file = outputFile
        samples.removeAll(keepingCapacity: true)
        targetURL = url
        startedAt = Date()
        input.installTap(onBus: 0, bufferSize: 1_024, format: sourceFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let rateRatio = targetFormat.sampleRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * rateRatio)) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var suppliedInput = false
            var conversionError: NSError?
            let conversionStatus = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
                if suppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard conversionError == nil,
                  conversionStatus != .error,
                  let channel = converted.floatChannelData?[0] else { return }
            let count = Int(converted.frameLength)
            self.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
            try? self.file?.write(from: converted)
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() throws -> AudioEvidenceRecord {
        guard let url = targetURL, let start = startedAt else { throw ArrangerLabError.invalidValue("audio recorder is not running") }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        let duration = Date().timeIntervalSince(start)
        let metrics = AudioAnalyzer.analyze(samples: samples, sampleRate: 48_000)
        targetURL = nil; startedAt = nil
        return .init(id: UUID(), relativePath: "audio/\(url.lastPathComponent)", sampleRate: 48_000, channels: 1, durationSeconds: duration, metrics: metrics)
    }

    public func stopSilently() {
        if engine.isRunning { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        file = nil; targetURL = nil; startedAt = nil; samples.removeAll()
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
