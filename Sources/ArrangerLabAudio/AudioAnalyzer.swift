import Accelerate
import ArrangerLabCore
import Foundation

public enum AudioAnalyzer {
    public static func analyze(samples: [Float], sampleRate: Double, spectrumBins: Int = 64) -> AudioMetrics {
        guard !samples.isEmpty else { return .init(rms: 0, peak: 0, rmsDBFS: -160, spectralCentroidHz: 0, normalizedSpectrum: Array(repeating: 0, count: spectrumBins)) }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        let frameSize = 2_048
        var candidates: [(start: Int, energy: Float)] = []
        if samples.count <= frameSize {
            candidates = [(0, samples.reduce(Float.zero) { $0 + $1 * $1 })]
        } else {
            var start = 0
            while start + frameSize <= samples.count {
                let energy = samples[start..<(start + frameSize)].reduce(Float.zero) { $0 + $1 * $1 }
                candidates.append((start, energy))
                start += frameSize / 2
            }
            let finalStart = samples.count - frameSize
            if candidates.last?.start != finalStart {
                let energy = samples[finalStart..<samples.count].reduce(Float.zero) { $0 + $1 * $1 }
                candidates.append((finalStart, energy))
            }
        }
        let selectedStarts = candidates.sorted { $0.energy > $1.energy }.prefix(12).map(\.start)
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        let stride = max(1, frameSize / 2 / spectrumBins)
        var spectrum = [Double](repeating: 0, count: spectrumBins)
        for start in selectedStarts {
            let available = min(frameSize, samples.count - start)
            var frame = Array(samples[start..<(start + available)])
            if frame.count < frameSize { frame += Array(repeating: 0, count: frameSize - frame.count) }
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(frameSize))
            var frameSpectrum = [Double](repeating: 0, count: spectrumBins)
            for bin in 0..<spectrumBins {
                let k = min(frameSize / 2 - 1, bin * stride + stride / 2)
                let omega = 2 * Double.pi * Double(k) / Double(frameSize)
                var real = 0.0, imaginary = 0.0
                for index in frame.indices {
                    let angle = omega * Double(index)
                    real += Double(frame[index]) * cos(angle)
                    imaginary -= Double(frame[index]) * sin(angle)
                }
                frameSpectrum[bin] = hypot(real, imaginary)
            }
            let frameTotal = frameSpectrum.reduce(0, +)
            if frameTotal > 0 {
                for bin in spectrum.indices { spectrum[bin] += frameSpectrum[bin] / frameTotal }
            }
        }
        let total = spectrum.reduce(0, +)
        if total > 0 { spectrum = spectrum.map { $0 / total } }
        let nyquist = sampleRate / 2
        let centroid = spectrum.enumerated().reduce(0.0) { partial, pair in
            partial + (Double(pair.offset) + 0.5) / Double(spectrumBins) * nyquist * pair.element
        }
        let db = rms > 0 ? 20 * log10(Double(rms)) : -160
        return .init(rms: Double(rms), peak: Double(peak), rmsDBFS: db, spectralCentroidHz: centroid, normalizedSpectrum: spectrum)
    }

    public static func spectralDistance(_ a: AudioMetrics, _ b: AudioMetrics) -> Double {
        let count = min(a.normalizedSpectrum.count, b.normalizedSpectrum.count)
        guard count > 0 else { return 0 }
        return sqrt(zip(a.normalizedSpectrum.prefix(count), b.normalizedSpectrum.prefix(count)).reduce(0) { sum, pair in
            let delta = pair.0 - pair.1
            return sum + delta * delta
        })
    }
}

public enum PA700EvidenceRules {
    public static func volumePasses(_ metrics: [AudioMetrics]) -> Bool {
        guard metrics.count == 3 else { return false }
        return metrics[0].rms < metrics[1].rms && metrics[1].rms < metrics[2].rms && metrics[2].rmsDBFS - metrics[0].rmsDBFS >= 6
    }

    public static func expressionPasses(_ metrics: [AudioMetrics]) -> Bool {
        guard metrics.count == 3 else { return false }
        return metrics[0].rms < metrics[1].rms && metrics[1].rms < metrics[2].rms && metrics[2].rmsDBFS - metrics[0].rmsDBFS >= 3
    }

    public static func presetABA(a1: AudioMetrics, b: AudioMetrics, a2: AudioMetrics) -> Bool {
        AudioAnalyzer.spectralDistance(a1, a2) < min(AudioAnalyzer.spectralDistance(a1, b), AudioAnalyzer.spectralDistance(a2, b))
    }
}
