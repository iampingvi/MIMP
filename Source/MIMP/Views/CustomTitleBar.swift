import SwiftUI

struct CustomTitleBar: View {
    @ObservedObject var player: AudioPlayer
    @Binding var showingAbout: Bool
    let height: CGFloat = 28
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        HStack(spacing: 0) {
            // Левая часть с кнопками
            HStack(spacing: 8) {
                WindowButton(
                    color: themeManager.isRetroMode ? .green : .red,
                    symbol: "xmark",
                    isRetroStyle: themeManager.isRetroMode
                )
                    .help("Close")
                    .onTapGesture {
                        NSApplication.shared.terminate(nil)
                    }
         
                
                WindowButton(
                    color: .gray, 
                    symbol: "info.circle",
                    isRetroStyle: themeManager.isRetroMode
                )
                    .help("About")
                    .onTapGesture {
                        showingAbout.toggle()
                    }
            }
            .padding(.leading, 12)
            
            // Центральная часть с названием
            Text(titleText)
                .font(.system(
                    size: 13,
                    design: themeManager.isRetroMode ? .monospaced : .default
                ))
                .foregroundColor(Color.retroText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .mask(
                    LinearGradient(
                        gradient: Gradient(colors: [.black, .black, .clear]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .background(WindowDraggingView())
                .onTapGesture(count: 2) {
                    if let window = NSApp.mainWindow {
                        window.toggleExpand()
                    }
                }
            
            // Правая часть с регулятором громкости
            VolumeControl(player: player)
                .padding(.trailing, 0)
        }
        .frame(height: height)
    }
    
    private var titleText: String {
        if let track = player.currentTrack {
            if !track.artist.isEmpty && track.artist != "Unknown Artist" {
                return "\(track.artist) - \(track.title)"
            }
            return track.title
        }
        return "MIMP | Minimal Interface Music Player"
    }
}

struct WindowButton: View {
    @StateObject private var themeManager = ThemeManager.shared
    let color: Color
    let symbol: String
    @State private var isHovered = false
    let isRetroStyle: Bool
    
    var body: some View {
        ZStack {
            if isRetroStyle {
                Rectangle()
                    .stroke(Color.retroText, lineWidth: 1)
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(color.opacity(isHovered ? 1.0 : 0.8))
                    .frame(width: 12, height: 12)
            }
            
            if isHovered || isRetroStyle {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isRetroStyle ? Color.retroText : Color.black.opacity(0.8))
            }
        }
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hover
            }
        }
    }
}

struct WindowDraggingView: NSViewRepresentable {
    class Coordinator: NSObject {
        var isDragging = false
        var initialLocation: NSPoint?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        let area = NSTrackingArea(rect: .zero,
                                 options: [.mouseEnteredAndExited, .activeInActiveApp, .mouseMoved, .inVisibleRect],
                                 owner: view,
                                 userInfo: nil)
        view.addTrackingArea(area)
        
        // Добавляем обработчик перетаскивания
        let dragGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(dragGesture)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension WindowDraggingView.Coordinator {
    @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let window = gesture.view?.window else { return }
        
        switch gesture.state {
        case .began:
            initialLocation = window.frame.origin
            isDragging = true
            
        case .changed:
            guard isDragging else { return }
            let translation = gesture.translation(in: nil)
            
            if let initialLocation = initialLocation {
                window.setFrameOrigin(NSPoint(
                    x: initialLocation.x + translation.x,
                    y: initialLocation.y + translation.y
                ))
            }
            
        case .ended, .cancelled:
            isDragging = false
            initialLocation = nil
            
        default:
            break
        }
    }
}
