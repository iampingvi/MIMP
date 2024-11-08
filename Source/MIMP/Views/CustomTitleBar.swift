import SwiftUI

struct CustomTitleBar: View {
    @ObservedObject var player: AudioPlayer
    @ObservedObject private var updateManager = UpdateManager.shared
    @Binding var showingAbout: Bool
    let height: CGFloat = 28
    @State private var autoUpdateEnabled = Settings.shared.autoUpdateEnabled
    @State private var isInitialAppearance = true
    @State private var isWindowPinned = Settings.shared.isWindowPinned
    @State private var isCompactMode = Settings.shared.isCompactMode
    
    var body: some View {
        ZStack {
            // Фоновый слой с текстом по центру
            GeometryReader { geometry in
                if player.currentTrack != nil {
                    // Show track info
                    Text(titleText)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .opacity(0.7)
                        .lineLimit(1)
                        .frame(width: geometry.size.width * 0.7, alignment: .center)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .contentShape(Rectangle())
                        .mask(
                            LinearGradient(
                                gradient: Gradient(colors: [.clear, .black, .black, .black, .clear]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .animation(.none, value: isCompactMode)
                        )
                        .opacity(player.isLoading ? 0 : 1)
                        .animation(.none, value: isCompactMode)
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
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .opacity(0.7)
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
                            .animation(.none, value: isCompactMode)
                        )
                        .animation(.none, value: isCompactMode)
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
            .transaction { transaction in 
                transaction.animation = nil  // Отключаем анимацию для фонового слоя
            }
            
            // Передний слой с копками
            HStack {
                // Левая часть с кнопками
                HStack(spacing: 8) {
                    // Кнопка закрытия
                    WindowButton(
                        color: .red,
                        symbol: "xmark"
                    )
                    .help("Close")
                    .onTapGesture {
                        NSApplication.shared.terminate(nil)
                    }
                    
                    // Кнопка компактного режима
                    WindowButton(
                        color: isCompactMode ? Color(red: 0.93, green: 0.73, blue: 0.0) : Color(red: 0.2, green: 0.8, blue: 0.2),
                        symbol: isCompactMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
                    )
                    .help(isCompactMode ? "Expand View" : "Compact View")
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCompactMode.toggle()
                            Settings.shared.isCompactMode = isCompactMode
                        }
                    }
                    
                    // Кнопка About
                    WindowButton(
                        color: .gray, 
                        symbol: "info.circle"
                    )
                    .help("About")
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingAbout.toggle()
                        }
                    }
                    
                    // Кнопка обновления
                    if updateManager.isUpdateAvailable && autoUpdateEnabled {
                        WindowButton(
                            color: .blue,
                            symbol: "arrow.triangle.2.circlepath"
                        )
                        .help("Update Available")
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                updateManager.showingUpdate = true
                            }
                        }
                    }
                }
                .padding(.leading, 12)
                
                Spacer()
                
                // Правая часть с регулятором громкости и кнопкой закрепления окна
                HStack(spacing: 2) {
                    // Кнопка закрепления окна
                    WindowButton(
                        color: isWindowPinned ? NSColor.controlAccentColor.asColor : .white.opacity(0.5),
                        symbol: isWindowPinned ? "pin.fill" : "pin.fill"
                    )
                    .help(isWindowPinned ? "Unpin Window" : "Pin Window")
                    .onTapGesture {
                        isWindowPinned.toggle()
                        Settings.shared.isWindowPinned = isWindowPinned
                        if let window = NSApp.mainWindow {
                            window.level = isWindowPinned ? .floating : .normal
                        }
                    }
                    
                    // Регулятор громкости
                    VolumeControl(player: player)
                }
                .padding(.trailing, 8)
                .id("volumeControl")
            }
            .transaction { transaction in
                transaction.animation = nil  // Отключаем анимацию для кнопок
            }
        }
        .frame(height: height)
        .transaction { transaction in
            transaction.animation = nil  // Отклюаем анимацию для всего тайтлбара
        }
        .background(Color.clear)
        .zIndex(100) // Гарантируем, что тайтлбар всегда поверх
        .onAppear {
            // Delay setting isInitialAppearance to false to avoid initial flash
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInitialAppearance = false
            }
            
            // Set initial window level based on saved setting
            if let window = NSApp.mainWindow {
                window.level = isWindowPinned ? .floating : .normal
            }
            
            // Добавляем передачу привязок в HotKeys
            HotKeys.shared.setWindowBindings(
                isCompactMode: Binding(
                    get: { self.isCompactMode },
                    set: { self.isCompactMode = $0 }
                ),
                isWindowPinned: Binding(
                    get: { self.isWindowPinned },
                    set: { self.isWindowPinned = $0 }
                )
            )
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
    let color: Color
    let symbol: String
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            // Only show circle background for non-pin buttons
            if !symbol.contains("pin") {
                Circle()
                    .fill(color.opacity(isHovered ? 1.0 : 0.8))
                    .frame(width: 12, height: 12)
            }
            
            // For pin button, show just the icon with color
            if symbol.contains("pin") {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color)
                    .rotationEffect(.degrees(-45))
                    .scaleEffect(x: -1, y: 1)
            }
            // For other buttons, show icon only on hover
            else if isHovered {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(color == .white ? color : .black.opacity(0.8))
            }
        }
        .frame(width: 12, height: 12)
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
        let view = DraggableView()
        view.wantsLayer = true
        
        let area = NSTrackingArea(rect: .zero,
                                 options: [.mouseEnteredAndExited, .activeInActiveApp, .mouseMoved, .inVisibleRect],
                                 owner: view,
                                 userInfo: nil)
        view.addTrackingArea(area)
        
        // Добавляем обработчик перетаскивания
        let dragGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(dragGesture)
        
        // Добавляем обработчик двойного клика
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
        clickGesture.numberOfClicksRequired = 2
        view.addGestureRecognizer(clickGesture)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

extension WindowDraggingView.Coordinator {
    @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard let window = gesture.view?.window else { return }
        
        switch gesture.state {
        case .began:
            // Если окно развернуто, эмулируем двойной клик перед началом перетаскивания
            if Settings.shared.isWindowExpanded {
                handleDoubleClick(NSClickGestureRecognizer(target: nil, action: nil))
                // Немного подождем, пока окно изменит размер
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.initialLocation = window.frame.origin
                }
            } else {
                initialLocation = window.frame.origin
            }
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
    
    @objc func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        if let window = gesture.view?.window {
            window.toggleExpand()
        }
    }
}

extension NSColor {
    var asColor: Color {
        Color(nsColor: self)
    }
}
