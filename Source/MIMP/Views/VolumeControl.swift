import SwiftUI

struct VolumeControl: View {
    @ObservedObject var player: AudioPlayer
    @State private var isHovered = false
    
    var volumeIcon: String {
        if player.isMuted || player.volume == 0 {
            return "speaker.slash.fill"
        } else if player.volume < 0.33 {
            return "speaker.fill"
        } else if player.volume < 0.66 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Кнопка мута
            Button(action: { player.toggleMute() }) {
                HStack {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 10))
                        .frame(width: 10, alignment: .leading)
                        .animation(.smooth, value: volumeIcon)
                        .imageScale(.medium)
                        .symbolRenderingMode(.monochrome)
                }
                .frame(width: 20)
                .foregroundColor(player.isMuted || player.volume == 0 ? 
                    Color.white.opacity(0.3) : 
                    .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Mute")
            
            // Слайдер громкости
            Slider(
                value: Binding(
                    get: { Double(player.volume) },
                    set: { player.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .frame(width: 50)
            .controlSize(.mini)
            .tint(.white)
            .help("Volume")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .opacity(isHovered ? 0 : 0)
        )
        .onHover { isHovered = $0 }
    }
} 
