import SwiftUI
import AVFoundation

struct WaveformView: View {
    let url: URL
    let currentTime: TimeInterval
    let duration: TimeInterval
    var onSeek: ((TimeInterval) -> Void)?
    
    @State private var waveformSamples: [Float] = []
    @State private var hoveredX: CGFloat?
    @State private var error: Error?
    
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if !waveformSamples.isEmpty {
                    // Waveform visualization
                    Canvas { context, size in
                        let width = size.width
                        let height = size.height
                        let middle = height / 2
                        let pointSpacing = width / CGFloat(waveformSamples.count)
                        let progressWidth = width * CGFloat(currentTime / duration)
                        
                        for (index, sample) in waveformSamples.enumerated() {
                            let x = CGFloat(index) * pointSpacing
                            let amplitude = CGFloat(sample) * (height / 2)
                            
                            let topY = middle - amplitude
                            let bottomY = middle + amplitude
                            
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: topY))
                            path.addLine(to: CGPoint(x: x, y: bottomY))
                            
                            let color = x <= progressWidth ? 
                                (themeManager.isRetroMode ? 
                                    Color.green.opacity(0.6 + Double(sample) * 0.4) :
                                    Color.accentColor.opacity(0.6 + Double(sample) * 0.4)) :
                                (themeManager.isRetroMode ? 
                                    Color.green.opacity(0.3 + Double(sample) * 0.4) :
                                    Color.white.opacity(0.3 + Double(sample) * 0.4))
                            context.stroke(path, with: .color(color), lineWidth: 2)
                        }
                    }
                    
                    // Progress indicator
                    Rectangle()
                        .fill(Color.retroAccent.opacity(0.5))
                        .frame(width: 2)
                        .position(x: geometry.size.width * CGFloat(currentTime / duration), y: geometry.size.height / 2)
                    
                    // Hover indicator
                    if let x = hoveredX {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 2)
                            .position(x: x, y: geometry.size.height / 2)
                    }
                }
            }
            .opacity(waveformSamples.isEmpty ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: !waveformSamples.isEmpty)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hoveredX = value.location.x
                        let progress = value.location.x / geometry.size.width
                        onSeek?(duration * Double(progress))
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            hoveredX = nil
                        }
                    }
            )
            .onAppear {
                loadWaveform()
            }
        }
    }
    
    private func loadWaveform() {
        Task {
            error = nil
            
            do {
                let asset = AVURLAsset(url: url)
                let assetReader = try AVAssetReader(asset: asset)
                
                guard let audioTrack = try await asset.load(.tracks).first else { throw WaveformError.noAudioTrack }
                
                let outputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
                
                let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
                assetReader.add(readerOutput)
                
                guard assetReader.startReading() else {
                    throw WaveformError.failedToRead
                }
                
                var samples: [Float] = []
                let targetSampleCount = 200
                var sampleBuffer: [Float] = []
                let dynamicThreshold: Float = 0.1 // Порог для фильтрации шума
                
                while let buffer = readerOutput.copyNextSampleBuffer() {
                    let bufferLength = CMSampleBufferGetNumSamples(buffer)
                    guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
                    
                    var audioData = Data()
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    audioData.count = length
                    
                    _ = audioData.withUnsafeMutableBytes { ptr in
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                    }
                    
                    audioData.withUnsafeBytes { ptr in
                        let int16Ptr = ptr.bindMemory(to: Int16.self)
                        for i in 0..<bufferLength {
                            let sample = abs(Float(int16Ptr[i]) / Float(Int16.max))
                            // Применяем порог для фильтрации фонового шума
                            if sample > dynamicThreshold {
                                sampleBuffer.append(sample)
                            } else {
                                sampleBuffer.append(0)
                            }
                        }
                    }
                }
                
                // Улучшенный алгоритм даунсэмплинга
                let samplesPerPoint = max(1, sampleBuffer.count / targetSampleCount)
                for i in 0..<targetSampleCount {
                    let startIndex = i * samplesPerPoint
                    let endIndex = min(startIndex + samplesPerPoint, sampleBuffer.count)
                    if startIndex < endIndex {
                        let segment = sampleBuffer[startIndex..<endIndex]
                        let rms = sqrt(segment.reduce(0) { $0 + $1 * $1 } / Float(segment.count))
                        samples.append(rms)
                    }
                }
                
                // Нормализация с учетом динамического диапазона
                if let maxValue = samples.max(), maxValue > 0 {
                    let normalizedSamples = samples.map { value in
                        let normalized = value / maxValue
                        return normalized * normalized // Квадратичная нормализация для лучшего отображения динамики
                    }
                    await MainActor.run {
                        self.waveformSamples = normalizedSamples
                    }
                }
            } catch {
                print("Error loading waveform:", error)
                await MainActor.run {
                    self.error = error
                }
            }
        }
    }
}

enum WaveformError: Error {
    case noAudioTrack
    case failedToRead
} 