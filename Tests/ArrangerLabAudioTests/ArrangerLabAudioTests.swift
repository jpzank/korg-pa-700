import Foundation
import Testing
@testable import ArrangerLabAudio

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
}
