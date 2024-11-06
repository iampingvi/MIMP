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
                .task {
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
                            
                            // Создаем background view для тени
                            let backgroundView = NSView(frame: visualEffect.bounds)
                            backgroundView.wantsLayer = true
                            backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
                            backgroundView.layer?.cornerRadius = 10
                            backgroundView.layer?.shadowColor = NSColor.black.cgColor
                            backgroundView.layer?.shadowOpacity = 0.2
                            backgroundView.layer?.shadowOffset = CGSize(width: 0, height: -2)
                            backgroundView.layer?.shadowRadius = 12
                            backgroundView.layer?.masksToBounds = false
                            
                            // Добавляем background view под visualEffect
                            if let superView = visualEffect.superview {
                                superView.addSubview(backgroundView, positioned: .below, relativeTo: visualEffect)
                                
                                // Обновляем frame при изменении размера окна
                                NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: visualEffect, queue: .main) { _ in
                                    backgroundView.frame = visualEffect.frame
                                }
                            }
                            
                            // Настраиваем visualEffect
                            visualEffect.material = .windowBackground
                            visualEffect.state = .active
                            visualEffect.isEmphasized = false
                            visualEffect.layer?.cornerRadius = 10
                            visualEffect.layer?.masksToBounds = true
                        }

                        // Configure content view
                        if let contentView = window.contentView {
                            contentView.wantsLayer = true
                            contentView.layer?.cornerRadius = 10
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
    func set(titlebarColor: NSColor) {
        guard let titlebarView = standardWindowButton(.closeButton)?.superview?.superview else { return }
        titlebarView.wantsLayer = true
        titlebarView.layer?.backgroundColor = titlebarColor.cgColor
    }

    @objc func toggleExpand() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let currentFrame = self.frame

        if currentFrame.width < screen.width {
            // Expand the window to full screen width
            let newFrame = NSRect(
                x: screen.minX,
                y: currentFrame.minY,
                width: screen.width,
                height: currentFrame.height
            )
            self.setFrame(newFrame, display: true, animate: true)
        } else {
            // Restore to standard size
            let newFrame = NSRect(
                x: screen.midX - 400, // center the window
                y: currentFrame.minY,
                width: 800,
                height: currentFrame.height
            )
            self.setFrame(newFrame, display: true, animate: true)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Check if app was launched with file
        if let appleEvent = NSAppleEventManager.shared().currentAppleEvent,
           appleEvent.eventClass == kCoreEventClass,
           appleEvent.eventID == kAEOpenDocuments {
            Settings.shared.launchedWithFile = true
        } else {
            // Only reset if it wasn't launched with file
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
