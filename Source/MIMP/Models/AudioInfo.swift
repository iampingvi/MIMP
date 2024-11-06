import SwiftUI

struct AudioInfo {
    let format: String
    let bitRate: Int
    let sampleRate: Int
    let channels: Int
    
    var description: String {
        "\(format) | \(bitRate) kbps | \(sampleRateDescription) | \(channelsDescription)"
    }
    
    private var sampleRateDescription: String {
        let kHz = Double(sampleRate) / 1000.0
        return String(format: "%.1f kHz", kHz)
    }
    
    private var channelsDescription: String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        default: return "\(channels) channels"
        }
    }
    
    @ViewBuilder
    func view() -> some View {
        HStack(spacing: 16) {
            ForEach([
                (format, "music.note.list"),
                (bitRate > 0 ? "\(bitRate) kbps" : "N/A", "gauge.with.needle"),
                (sampleRateDescription, "waveform"),
                (channelsDescription, "speaker.wave.2")
            ], id: \.0) { text, icon in
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                    Text(text)
                        .font(.system(
                            size: 10,
                            weight: .medium,
                            design: ThemeManager.shared.isRetroMode ? .monospaced : .default
                        ))
                }
                .foregroundColor(Color.retroText.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
} 