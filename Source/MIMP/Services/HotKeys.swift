import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreServices

@MainActor
class HotKeys {
    static let shared = HotKeys()
    
    private var pressedKeys: Set<String> = []
    private var lastKeyPressTime: Date = Date()
    
    private var showingAbout: Binding<Bool>?
    private var updateManager: UpdateManager?
    private var isCompactMode: Binding<Bool>?
    private var isWindowPinned: Binding<Bool>?
    
    private init() {}
    
    func setBindings(showingAbout: Binding<Bool>, updateManager: UpdateManager) {
        self.showingAbout = showingAbout
        self.updateManager = updateManager
    }
    
    func setWindowBindings(isCompactMode: Binding<Bool>, isWindowPinned: Binding<Bool>) {
        self.isCompactMode = isCompactMode
        self.isWindowPinned = isWindowPinned
    }
    
    func setupKeyboardMonitoring(for player: AudioPlayer) -> Any? {
        // Monitor keyDown events
        let keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // 1. First check Command combinations
            if event.modifierFlags.contains(.command) {
                switch event.keyCode {
                case 12: // Cmd+Q (quit)
                    NSApplication.shared.terminate(nil)
                    return nil
                case 4:  // Cmd+H (hide)
                    NSApplication.shared.hide(nil)
                    return nil
                case 46: // Cmd+M (minimize)
                    NSApp.mainWindow?.miniaturize(nil)
                    return nil
                default:
                    break
                }
            }
            
            // 2. Check for I, U, and S keys without modifiers
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [] {
                switch event.keyCode {
                case 34: // i key (keyCode 34 is 'i' on all layouts)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        // Если открыто окно обновления, закрываем его
                        if self.updateManager?.showingUpdate == true {
                            self.updateManager?.showingUpdate = false
                        }
                        // Переключаем окно About
                        self.showingAbout?.wrappedValue.toggle()
                    }
                    return nil
                    
                case 32: // u key (keyCode 32 is 'u' on all layouts)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        // Если открыто окно About, закрываем его
                        if self.showingAbout?.wrappedValue == true {
                            self.showingAbout?.wrappedValue = false
                        }
                        // Проверяем наличие обновления перед переключением окна
                        if self.updateManager?.isUpdateAvailable == true {
                            self.updateManager?.toggleUpdateWindow()
                        } else {
                            // Опционально: можно добавить принудительную проверку обновлений
                            Task {
                                await self.updateManager?.checkForUpdates(force: true)
                            }
                        }
                    }
                    return nil
                    
                case 35: // P key (keyCode 35 is 'p' on all layouts)
                    if let isWindowPinned = self.isWindowPinned {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isWindowPinned.wrappedValue.toggle()
                            Settings.shared.isWindowPinned = isWindowPinned.wrappedValue
                            if let window = NSApp.mainWindow {
                                window.level = isWindowPinned.wrappedValue ? .floating : .normal
                            }
                        }
                    }
                    return nil
                    
                case 8: // C key (keyCode 8 is 'c' on all layouts)
                    if let isCompactMode = self.isCompactMode {
                        if !isCompactMode.wrappedValue {
                            // Анимация только при переходе В компактный режим
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isCompactMode.wrappedValue = true
                                Settings.shared.isCompactMode = true
                            }
                        } else {
                            // Без анимации при выходе ИЗ компактного режима
                            isCompactMode.wrappedValue = false
                            Settings.shared.isCompactMode = false
                        }
                    }
                    return nil
                    
                case 1: // S key (keyCode 1 is 's' on all layouts)
                    if player.isStopped {
                        // Если трек остановлен, запускаем его с начала
                        player.play()
                    } else {
                        // Если трек играет или на паузе, останавливаем его
                        player.stop()
                    }
                    return nil
                    
                default:
                    break
                }
            }
            
            // 3. Then check regular keys
            switch event.keyCode {
            case 49: // Space
                player.togglePlayPause()
                return nil
            case 123: // Left Arrow
                player.seekRelative(-3)
                return nil
            case 124: // Right Arrow
                player.seekRelative(3)
                return nil
            case 126: // Up Arrow
                player.adjustVolume(by: 0.05)
                return nil
            case 125: // Down Arrow
                player.adjustVolume(by: -0.05)
                return nil
            case 46: // M key (mute)
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [] {
                    player.toggleMute()
                    return nil
                }
            default:
                // Check for "deuse" sequence
                let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
                let currentTime = Date()
                
                if currentTime.timeIntervalSince(self.lastKeyPressTime) > 1.0 {
                    self.pressedKeys.removeAll()
                }
                self.lastKeyPressTime = currentTime
                self.pressedKeys.insert(key)
                
                let sequence = "deuse"
                if sequence.allSatisfy({ self.pressedKeys.contains(String($0)) }) {
                    self.resetDefaultPlayer()
                    self.pressedKeys.removeAll()
                    return nil
                }
            }
            
            return event
        }
        
        return keyDownMonitor
    }
    
    private func resetDefaultPlayer() {
        print("\n=== Resetting MIMP Default Player Settings ===")
        
        for format in AudioFormat.allCases {
            if let type = UTType(filenameExtension: format.rawValue) {
                print("\nResetting .\(format.rawValue)")
                
                let status = LSSetDefaultRoleHandlerForContentType(
                    type.identifier as CFString,
                    LSRolesMask.all,
                    "com.apple.quicktimeplayer" as CFString  // Reset to QuickTime Player
                )
                
                print(status == noErr ? "✓ Reset successful" : "✗ Reset failed")
            }
        }
        
        // Reset setting in Settings
        Settings.shared.isDefaultPlayerSet = false
        
        print("\n=== Reset Complete ===\n")
    }
} 