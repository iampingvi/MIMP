import SwiftUI

struct AudioInfoView: View {
    let audioInfo: AudioInfo
    @StateObject private var themeManager = ThemeManager.shared
    
    private var audioDetails: [(String, String)] {
        [
            (audioInfo.format, "music.note.list"),
            (audioInfo.bitRate > 0 ? "\(audioInfo.bitRate) kbps" : "N/A", "gauge.with.needle"),
            (audioInfo.sampleRate > 0 ? "\(audioInfo.sampleRate) Hz" : "N/A", "waveform"),
            (audioInfo.channels > 0 ? (audioInfo.channels == 1 ? "Mono" : "Stereo") : "N/A", "speaker.wave.2")
        ]
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(audioDetails, id: \.0) { text, icon in
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                    Text(text)
                        .font(.system(
                            size: 10,
                            weight: .medium,
                            design: themeManager.isRetroMode ? .monospaced : .default
                        ))
                }
                .foregroundColor(Color.retroText.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
} 
