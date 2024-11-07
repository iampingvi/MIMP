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
                        let barWidth = max(1.5, pointSpacing - 1)
                        let barSpacing = max(0.5, (pointSpacing - barWidth) / 2)
                        let maxAmplitude = height / 2.2
                        
                        for (index, sample) in waveformSamples.enumerated() {
                            let x = CGFloat(index) * pointSpacing + barSpacing
                            
                            let normalizedSample = pow(CGFloat(sample), 0.8)
                            let amplitude = normalizedSample * maxAmplitude
                            
                            let topAmplitude = amplitude
                            let bottomAmplitude = amplitude * 0.85
                            
                            // Calculate the progress for this specific bar
                            let barStartX = x
                            let barEndX = x + barWidth
                            
                            // Calculate how much of this bar should be filled
                            let fillProgress: CGFloat
                            if barEndX <= progressWidth {
                                fillProgress = 1.0 // Fully filled
                            } else if barStartX >= progressWidth {
                                fillProgress = 0.0 // Not filled
                            } else {
                                // Partially filled - calculate exact percentage
                                fillProgress = (progressWidth - barStartX) / barWidth
                            }
                            
                            // Draw background (unfilled) part
                            var backgroundPath = Path()
                            backgroundPath.addRect(CGRect(
                                x: x,
                                y: middle - topAmplitude,
                                width: barWidth,
                                height: topAmplitude
                            ))
                            backgroundPath.addRect(CGRect(
                                x: x,
                                y: middle,
                                width: barWidth,
                                height: bottomAmplitude
                            ))
                            
                            context.fill(backgroundPath, with: .color(Color.white.opacity(0.3 + Double(sample) * 0.4)))
                            
                            // Draw filled part
                            if fillProgress > 0 {
                                var filledPath = Path()
                                filledPath.addRect(CGRect(
                                    x: x,
                                    y: middle - topAmplitude,
                                    width: barWidth * fillProgress,
                                    height: topAmplitude
                                ))
                                filledPath.addRect(CGRect(
                                    x: x,
                                    y: middle,
                                    width: barWidth * fillProgress,
                                    height: bottomAmplitude
                                ))
                                
                                context.fill(filledPath, with: .color(Color.accentColor.opacity(0.6 + Double(sample) * 0.4)))
                            }
                        }
                    }
                    
                    // Progress indicator
                    let progressPosition = geometry.size.width * CGFloat(currentTime / duration)
                    let amplitudes = getAmplitudeAtPosition(progressPosition, size: geometry.size)
                    let barWidth = max(1.5, (geometry.size.width / CGFloat(waveformSamples.count)) - 1)
                    
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(width: barWidth, height: amplitudes.top)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.8))
                            .frame(width: barWidth, height: amplitudes.bottom)
                    }
                    .position(x: progressPosition, y: geometry.size.height / 2)
                    
                    // Hover indicator
                    if let x = hoveredX {
                        let hoverAmplitudes = getAmplitudeAtPosition(x, size: geometry.size)
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: barWidth, height: hoverAmplitudes.top)
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: barWidth, height: hoverAmplitudes.bottom)
                        }
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
                        let progress = max(0, min(value.location.x / geometry.size.width, 1.0))
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
    
    // В ZStack добавим функцию для получения амплитуды в текущей позиции
    func getAmplitudeAtPosition(_ position: CGFloat, size: CGSize) -> (top: CGFloat, bottom: CGFloat) {
        let index = Int((position / size.width) * CGFloat(waveformSamples.count))
        
        guard index >= 0 && index < waveformSamples.count else {
            return (0, 0)
        }
        
        let sample = waveformSamples[index]
        let normalizedSample = pow(CGFloat(sample), 0.8)
        let maxAmplitude = size.height / 2.2
        let topAmplitude = normalizedSample * maxAmplitude
        let bottomAmplitude = topAmplitude * 0.85
        
        return (topAmplitude, bottomAmplitude)
    }
}

enum WaveformError: Error {
    case noAudioTrack
    case failedToRead
} 