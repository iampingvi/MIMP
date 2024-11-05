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
                        window.hasShadow = true

                        // Configure window corner radius
                        window.contentView?.wantsLayer = true
                        window.contentView?.layer?.cornerRadius = 10
                        window.contentView?.layer?.masksToBounds = true

                        // Hide all standard window buttons
                        window.standardWindowButton(.closeButton)?.isHidden = true
                        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                        window.standardWindowButton(.zoomButton)?.isHidden = true

                        // Disable focus highlighting
                        if let visualEffect = window.contentView?.superview as? NSVisualEffectView {
                            visualEffect.wantsLayer = true
                            visualEffect.layer?.cornerRadius = 10
                            visualEffect.layer?.masksToBounds = true
                            visualEffect.material = .windowBackground
                            visualEffect.state = .active
                            visualEffect.isEmphasized = false
                        }

                        // Add double-click handler for the title bar
                        if let titlebarView = window.standardWindowButton(.closeButton)?.superview?.superview {
                            let clickGesture = NSClickGestureRecognizer(target: window, action: #selector(NSWindow.toggleExpand))
                            clickGesture.numberOfClicksRequired = 2
                            titlebarView.addGestureRecognizer(clickGesture)
                        }

                        // Force refresh the appearance
                        window.setFrame(window.frame, display: true)

                        // Additional settings to remove the border
                        if let visualEffect = window.contentView?.superview as? NSVisualEffectView {
                            visualEffect.wantsLayer = true
                            visualEffect.layer?.cornerRadius = 10
                            visualEffect.layer?.masksToBounds = true
                        }

                        // Activate the window to display in cmd+tab without changing the appearance
                        NSApp.setActivationPolicy(.regular)
                        window.level = .normal
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 120)
        .defaultPosition(.center)
        .commands {
            // Disable all standard menus
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .pasteboard) { }
            CommandGroup(replacing: .textEditing) { }
            CommandGroup(replacing: .windowList) { }
            CommandGroup(replacing: .windowSize) { }
            CommandGroup(replacing: .toolbar) { }
            CommandGroup(replacing: .help) { }
            CommandGroup(replacing: .appInfo) { }
        }
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
