import AVFoundation
import ArrangerLabCore
import Foundation
import Testing
@testable import ArrangerLabAudio

private enum AudioWriterTestError: Error {
    case failed
}

private final class TestAudioWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private let error: Error?
    private var writes = 0

    init(delay: TimeInterval = 0, error: Error? = nil) {
        self.delay = delay
        self.error = error
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        lock.lock()
        writes += 1
        lock.unlock()
        if let error {
            throw error
        }
    }

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return writes
    }
}

@Suite("ArrangerLabAudio")
struct ArrangerLabAudioTests {
    @Test func syntheticAudioMetrics() {
        let samples = (0..<4_800).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / 48_000) * 0.25)
        }
        let metrics = AudioAnalyzer.analyze(samples: samples, sampleRate: 48_000)
        #expect(metrics.rms > 0.17)
        #expect(metrics.rms < 0.18)
        #expect(abs(metrics.normalizedSpectrum.reduce(0, +) - 1) < 0.001)
    }

    @Test func recorderStopDrainsPendingWritesBeforeReturningEvidence() throws {
        let fixture = try makePipelineFixture(
            samples: [0.25, -0.25, 0.5, -0.5],
            writer: TestAudioWriter(delay: 0.05)
        )
        fixture.pipeline.enqueue(fixture.buffer)
        let recorder = AudioEvidenceRecorder(
            pipeline: fixture.pipeline,
            targetURL: URL(fileURLWithPath: "/tmp/Pending.caf"),
            startedAt: Date()
        )

        let evidence = try recorder.stop()

        #expect(fixture.writer.writeCount == 1)
        #expect(evidence.metrics == AudioAnalyzer.analyze(
            samples: fixture.samples,
            sampleRate: fixture.format.sampleRate
        ))
    }

    @Test func recorderStopSurfacesRetainedWriterFailure() throws {
        let fixture = try makePipelineFixture(
            samples: [0.25, -0.25],
            writer: TestAudioWriter(error: AudioWriterTestError.failed)
        )
        fixture.pipeline.enqueue(fixture.buffer)
        let recorder = AudioEvidenceRecorder(
            pipeline: fixture.pipeline,
            targetURL: URL(fileURLWithPath: "/tmp/Failed.caf"),
            startedAt: Date()
        )

        do {
            _ = try recorder.stop()
            Issue.record("stop() should surface the retained writer failure")
        } catch AudioWriterTestError.failed {
            #expect(fixture.writer.writeCount == 1)
        } catch {
            Issue.record("Unexpected stop() error: \(error)")
        }
    }

    @Test func boundedPipelineSurfacesBackpressureInsteadOfDroppingEvidence() throws {
        let writerStarted = DispatchSemaphore(value: 0)
        let releaseWriter = DispatchSemaphore(value: 0)
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try makeBuffer(samples: [0.25, -0.25], format: format)
        let pipeline = try #require(
            AudioEvidenceWritePipeline(
                sourceFormat: format,
                targetFormat: format,
                maximumPendingBuffers: 1
            ) { _ in
                writerStarted.signal()
                releaseWriter.wait()
            }
        )
        pipeline.enqueue(buffer)
        #expect(writerStarted.wait(timeout: .now() + 1) == .success)

        pipeline.enqueue(buffer)
        releaseWriter.signal()
        let recorder = AudioEvidenceRecorder(
            pipeline: pipeline,
            targetURL: URL(fileURLWithPath: "/tmp/Backpressure.caf"),
            startedAt: Date()
        )

        do {
            _ = try recorder.stop()
            Issue.record("A saturated pipeline should not return partial evidence")
        } catch let error as ArrangerLabError {
            #expect(
                error == .corruptCapture(
                    "audio evidence pipeline could not keep up with input"
                )
            )
        } catch {
            Issue.record("Unexpected stop() error: \(error)")
        }
    }

    private func makePipelineFixture(
        samples: [Float],
        writer: TestAudioWriter
    ) throws -> (
        pipeline: AudioEvidenceWritePipeline,
        buffer: AVAudioPCMBuffer,
        format: AVAudioFormat,
        samples: [Float],
        writer: TestAudioWriter
    ) {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try makeBuffer(samples: samples, format: format)
        let pipeline = try #require(
            AudioEvidenceWritePipeline(
                sourceFormat: format,
                targetFormat: format
            ) { buffer in
                try writer.write(buffer)
            }
        )
        return (pipeline, buffer, format, samples, writer)
    }

    private func makeBuffer(
        samples: [Float],
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        )
        let channel = try #require(buffer.floatChannelData?[0])
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }
}
