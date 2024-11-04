import Foundation
import AVFoundation

class AudioAnalyzer {
    private let minBPM: Double = 60
    private let maxBPM: Double = 200

    func analyzeAudio(url: URL) async throws -> AudioAnalysis {
        let file = try AVAudioFile(forReading: url)
        let frameCapacity = AVAudioFrameCount(file.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCapacity)
        
        guard let buffer = buffer else {
            throw AudioError.failedToAnalyze(NSError(domain: "", code: -1))
        }
        
        try file.read(into: buffer)
        
        let waveform = generateWaveform(buffer: buffer)
        let bpm = analyzeBPM(buffer: buffer)

        return AudioAnalysis(
            bpm: bpm,
            key: "-",
            waveform: waveform
        )
    }

    private func analyzeBPM(buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else {
            return 120.0
        }

        let frameLength = Int(buffer.frameLength)
        let sampleRate = Double(buffer.format.sampleRate)

        var amplitudes = Array(UnsafeBufferPointer(start: channelData,
                                                  count: frameLength))
            .map(abs)

        amplitudes = lowPassFilter(amplitudes)
        let peaks = findPeaks(in: amplitudes)

        guard peaks.count > 1 else { return 120.0 }

        let intervals = peaks.windows(ofCount: 2)
            .map { Double($0[1] - $0[0]) / sampleRate }
            .filter { $0 > 0 }

        guard let avgInterval = intervals.average, avgInterval > 0 else {
            return 120.0
        }

        let bpm = 60.0 / avgInterval
        return min(max(round(bpm), minBPM), maxBPM)
    }

    private func lowPassFilter(_ data: [Float]) -> [Float] {
        let alpha: Float = 0.1
        var filtered = [Float](repeating: 0, count: data.count)
        filtered[0] = data[0]

        for i in 1..<data.count {
            filtered[i] = filtered[i-1] + alpha * (data[i] - filtered[i-1])
        }

        return filtered
    }

    private func findPeaks(in data: [Float]) -> [Int] {
        guard data.count > 2 else { return [] }

        let threshold = (data.max() ?? 1.0) * 0.5
        var peaks = [Int]()

        for i in 1..<(data.count - 1) where data[i] > threshold {
            if data[i] > data[i-1] && data[i] > data[i+1] {
                peaks.append(i)
            }
        }

        return peaks
    }

    private func generateWaveform(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else {
            return []
        }

        let frameLength = Int(buffer.frameLength)
        let pointCount = 200
        let samplesPerPoint = max(1, frameLength / pointCount)

        return (0..<pointCount).map { i in
            let startSample = i * samplesPerPoint
            let endSample = min(startSample + samplesPerPoint, frameLength)

            guard startSample < endSample else { return 0 }

            let samples = UnsafeBufferPointer(start: channelData + startSample,
                                            count: endSample - startSample)
            return samples.map(abs).max() ?? 0
        }
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

private extension Array {
    func windows(ofCount count: Int) -> [[Element]] {
        guard count > 0, self.count >= count else { return [] }
        return (0...self.count - count).map {
            Array(self[$0..<$0 + count])
        }
    }
}

struct AudioAnalysis {
    let bpm: Double
    let key: String
    let waveform: [Float]
}
