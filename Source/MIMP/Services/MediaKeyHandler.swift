import Foundation
import Cocoa
import Carbon

class MediaKeyHandler {
    static let shared = MediaKeyHandler()
    private var callback: (() -> Void)?
    private var eventHandler: EventHandlerRef?

    private init() {
        setupEventHandler()
    }

    private func setupEventHandler() {
        // Create an event type specification for media keys
        var eventType = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Create a callback for handling events
        let callback: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            let error = GetEventParameter(
                eventRef,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if error == noErr {
                if hotKeyID.id == 1 { // Play/Pause key
                    DispatchQueue.main.async {
                        MediaKeyHandler.shared.callback?()
                    }
                    return noErr
                }
            }

            return OSStatus(eventNotHandledErr)
        }

        // Register the event handler
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &handler
        )

        if status == noErr {
            self.eventHandler = handler

            // Register a hotkey for Play/Pause
            var hotKeyID = EventHotKeyID(signature: 0x4D4B4859, id: 1) // MKHY
            var hotKeyRef: EventHotKeyRef?

            RegisterEventHotKey(
                UInt32(kVK_F8),
                0,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
        }
    }

    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    func setCallback(_ callback: @escaping () -> Void) {
        self.callback = callback
    }
}
