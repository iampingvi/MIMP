import SwiftUI

struct CustomTitleBar: View {
    @ObservedObject var player: AudioPlayer
    @ObservedObject private var updateManager = UpdateManager.shared
    @Binding var showingAbout: Bool
    let height: CGFloat = 28
    @StateObject private var themeManager = ThemeManager.shared
    @State private var autoUpdateEnabled = Settings.shared.autoUpdateEnabled
    @State private var isInitialAppearance = true
    
    var body: some View {
        ZStack {
            // Фоновый слой с текстом по центру
            GeometryReader { geometry in
                if player.currentTrack != nil {
                    // Show track info
                    Text(titleText)
                        .font(.system(
                            size: 13,
                            design: themeManager.isRetroMode ? .monospaced : .default
                        ))
                        .foregroundColor(Color.retroText)
                        .lineLimit(1)
                        .frame(width: geometry.size.width * 0.75, alignment: .center)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .contentShape(Rectangle())
                        .mask(
                            LinearGradient(
                                gradient: Gradient(colors: [.clear, .black, .black, .black, .clear]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(player.isLoading ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: player.isLoading)
                        .background(WindowDraggingView())
                        .onTapGesture(count: 2) {
                            if let window = NSApp.mainWindow {
                                window.toggleExpand()
                            }
                        }
                } else if !Settings.shared.launchedWithFile && !player.isLoading && !isInitialAppearance {
                    // Show app name only in drag-n-drop view and not on initial appearance
                    Text("Minimal Interface Music Player")
                        .font(.system(
                            size: 13,
                            design: themeManager.isRetroMode ? .monospaced : .default
                        ))
                        .foregroundColor(Color.retroText)
                        .lineLimit(1)
                        .frame(width: geometry.size.width * 0.75, alignment: .center)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .contentShape(Rectangle())
                        .mask(
                            LinearGradient(
                                gradient: Gradient(colors: [.clear, .black, .black, .black, .clear]),
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
                } else {
                    // Empty title with dragging enabled
                    WindowDraggingView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            
            // Передний слой с кнопками
            HStack {
                // Левая часть с кнопками
                HStack(spacing: 8) {
                    // Кнопка закрытия
                    WindowButton(
                        color: themeManager.isRetroMode ? .green : .red,
                        symbol: "xmark",
                        isRetroStyle: themeManager.isRetroMode
                    )
                    .help("Close")
                    .onTapGesture {
                        NSApplication.shared.terminate(nil)
                    }
                    
                    // Кнопка About
                    WindowButton(
                        color: .gray, 
                        symbol: "info.circle",
                        isRetroStyle: themeManager.isRetroMode
                    )
                    .help("About")
                    .onTapGesture {
                        showingAbout.toggle()
                    }
                    
                    // Кнопка обновления
                    if updateManager.isUpdateAvailable && autoUpdateEnabled {
                        WindowButton(
                            color: .blue,
                            symbol: "arrow.triangle.2.circlepath",
                            isRetroStyle: themeManager.isRetroMode
                        )
                        .help("Update Available")
                        .onTapGesture {
                            updateManager.showingUpdate = true
                        }
                    }
                }
                .padding(.leading, 12)
                
                Spacer()
                
                // Правая часть с регулятором громкости
                VolumeControl(player: player)
                    .padding(.trailing, 8)
            }
        }
        .frame(height: height)
        .onAppear {
            // Delay setting isInitialAppearance to false to avoid initial flash
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInitialAppearance = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            autoUpdateEnabled = Settings.shared.autoUpdateEnabled
        }
    }
    
    private var titleText: String {
        if let track = player.currentTrack {
            if !track.artist.isEmpty && track.artist != "Unknown Artist" {
                return "\(track.artist) - \(track.title)"
            }
            return track.title
        }
        return ""  // Empty string by default
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
