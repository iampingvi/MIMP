import SwiftUI

struct AudioInfoView: View {
    let audioInfo: AudioInfo
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach([
                (audioInfo.format, "music.note.list"),
                ("\(audioInfo.bitRate) kbps", "gauge.with.needle"),
                ("\(audioInfo.sampleRate) Hz", "waveform"),
                (audioInfo.channels == 1 ? "Mono" : "Stereo", "speaker.wave.2")
            ], id: \.0) { text, icon in
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
