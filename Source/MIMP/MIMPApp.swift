import SwiftUI
import AppKit

@main
struct MIMPApp: App {
    @StateObject private var player = AudioPlayer.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Disable automatic window tabbing
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(player)
                .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: Settings.shared.isCompactMode)
                .task { @MainActor in
                    // Restore playback state after update
                    if Settings.shared.wasUpdated,
                       let lastTrackURL = Settings.shared.lastTrackURL {
                        let wasPlaying = Settings.shared.lastTrackWasPlaying
                        let position = Settings.shared.lastTrackPosition
                        
                        Task {
                            do {
                                try await player.load(url: lastTrackURL)
                                if wasPlaying {
                                    player.play()
                                }
                            } catch {
                                print("Failed to restore playback:", error)
                            }
                        }
                        
                        // Reset the update flag
                        Settings.shared.wasUpdated = false
                    }
                    
                    if let window = NSApp.windows.first {
                        // Configure window styles
                        window.styleMask = [.borderless, .fullSizeContentView]
                        window.titlebarAppearsTransparent = true
                        window.isMovableByWindowBackground = true
                        window.backgroundColor = .clear
                        window.hasShadow = false
                        
                        // Configure visual effect view
                        if let visualEffect = window.contentView?.superview as? NSVisualEffectView {
                            visualEffect.wantsLayer = true
                            
                            // Создаем background view для тени без анимации
                            let backgroundView = NSView(frame: visualEffect.bounds)
                            backgroundView.wantsLayer = true
                            backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
                            backgroundView.layer?.cornerRadius = Settings.shared.isWindowExpanded ? 0 : 10
                            backgroundView.layer?.shadowColor = NSColor.black.cgColor
                            backgroundView.layer?.shadowOpacity = 0.2
                            backgroundView.layer?.shadowOffset = CGSize(width: 0, height: -2)
                            backgroundView.layer?.shadowRadius = 12
                            backgroundView.layer?.masksToBounds = false
                            
                            // Отключаем анимации для изменений layer
                            CATransaction.begin()
                            CATransaction.setDisableActions(true)
                            
                            // Добавляем background view под visualEffect
                            if let superView = visualEffect.superview {
                                superView.addSubview(backgroundView, positioned: .below, relativeTo: visualEffect)
                            }
                            
                            CATransaction.commit()
                            
                            // Настраиваем visualEffect без анимаций
                            visualEffect.material = .windowBackground
                            visualEffect.state = .active
                            visualEffect.isEmphasized = false
                            visualEffect.layer?.cornerRadius = Settings.shared.isWindowExpanded ? 0 : 10
                            visualEffect.layer?.masksToBounds = true
                        }

                        // Configure content view
                        if let contentView = window.contentView {
                            contentView.wantsLayer = true
                            contentView.layer?.cornerRadius = Settings.shared.isWindowExpanded ? 0 : 10
                            contentView.layer?.masksToBounds = true
                        }

                        // Hide standard window buttons
                        window.standardWindowButton(.closeButton)?.isHidden = true
                        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                        window.standardWindowButton(.zoomButton)?.isHidden = true
                        
                        // Set window level based on settings
                        window.level = Settings.shared.isWindowPinned ? .floating : .normal
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 120)
        .defaultPosition(.center)
        .commandsRemoved()
    }
}

extension NSWindow {
    static var lastWindowPositionX: CGFloat?
    
    func set(titlebarColor: NSColor) {
        guard let titlebarView = standardWindowButton(.closeButton)?.superview?.superview else { return }
        titlebarView.wantsLayer = true
        titlebarView.layer?.backgroundColor = titlebarColor.cgColor
    }

    func toggleExpand() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let currentFrame = self.frame
        
        if currentFrame.width < screen.width - 20 {
            // Сохраняем текущую позицию
            NSWindow.lastWindowPositionX = currentFrame.minX
            
            // Рассчитываем новую позицию и размер
            let newWidth = screen.width
            let newFrame = NSRect(
                x: screen.minX,
                y: currentFrame.minY,
                width: newWidth,
                height: currentFrame.height
            )
            
            // Настраиваем анимацию в стиле macOS
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1) // Стиль macOS
                context.allowsImplicitAnimation = false
                
                // Обновляем UI
                Settings.shared.isWindowExpanded = true
                self.contentView?.layer?.cornerRadius = 0
                if let visualEffect = self.contentView?.superview as? NSVisualEffectView {
                    visualEffect.layer?.cornerRadius = 0
                    if let backgroundView = visualEffect.superview?.subviews.first(where: { $0 != visualEffect }) {
                        backgroundView.layer?.cornerRadius = 0
                    }
                }
                
                // Анимируем изменение размера
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            restoreToStandardSize()
        }
    }
    
    func restoreToStandardSize() {
        let standardWidth: CGFloat = 800
        let newFrame = NSRect(
            x: NSWindow.lastWindowPositionX ?? self.frame.minX,
            y: self.frame.minY,
            width: standardWidth,
            height: self.frame.height
        )
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1) // Стиль macOS
            context.allowsImplicitAnimation = false
            
            // Обновляем UI
            Settings.shared.isWindowExpanded = false
            self.contentView?.layer?.cornerRadius = 10
            if let visualEffect = self.contentView?.superview as? NSVisualEffectView {
                visualEffect.layer?.cornerRadius = 10
                if let backgroundView = visualEffect.superview?.subviews.first(where: { $0 != visualEffect }) {
                    backgroundView.layer?.cornerRadius = 10
                }
            }
            
            // Анимируем изменение размера
            self.animator().setFrame(newFrame, display: true)
        }
        
        NSWindow.lastWindowPositionX = nil
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Check if app was launched with file or after update
        if let appleEvent = NSAppleEventManager.shared().currentAppleEvent,
           appleEvent.eventClass == kCoreEventClass,
           appleEvent.eventID == kAEOpenDocuments {
            Settings.shared.launchedWithFile = true
        } else if Settings.shared.wasUpdated {
            // Keep the wasUpdated flag if we're restoring after update
            Settings.shared.launchedWithFile = false
        } else {
            Settings.shared.launchedWithFile = false
        }
    }
    
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first,
              AudioFormat.allExtensions.contains(url.pathExtension.lowercased()) else {
            return
        }

        // Set the flag when opening file
        Settings.shared.launchedWithFile = true

        // Activate the existing window
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        Task {
            try? await AudioPlayer.shared.load(url: url)
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the flag if it was set during launch
        if !Settings.shared.launchedWithFile {
            // Only reset if it wasn't launched with file
            Settings.shared.launchedWithFile = false
        }
    }
}
