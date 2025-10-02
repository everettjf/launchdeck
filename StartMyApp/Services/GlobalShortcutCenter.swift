import AppKit
import Carbon

final class GlobalShortcutCenter {
    static let shared = GlobalShortcutCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?

    private init() {}

    func register(shortcut: KeyboardShortcutPreference, handler: @escaping () -> Void) {
        unregister()
        callback = handler

        var hotKeyID = EventHotKeyID(signature: "SMAP".fourCharCode, id: UInt32(1))
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalShortcutCenter>.fromOpaque(userData).takeUnretainedValue()
            manager.handle(event: event)
            return noErr
        }, 1, &eventSpec, selfPointer, &eventHandler)

        guard status == noErr else {
            unregister()
            return
        }

        let registration = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                               shortcut.modifiers.carbonFlags,
                                               hotKeyID,
                                               GetApplicationEventTarget(),
                                               0,
                                               &hotKeyRef)

        if registration != noErr {
            unregister()
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
        callback = nil
    }

    private func handle(event: EventRef?) {
        guard let event else { return }
        let kind = GetEventKind(event)
        switch kind {
        case UInt32(kEventHotKeyPressed):
            callback?()
        default:
            break
        }
    }

    deinit {
        unregister()
    }
}

private extension String {
    var fourCharCode: OSType {
        var result: OSType = 0
        for scalar in unicodeScalars.prefix(4) {
            result = (result << 8) + OSType(scalar.value)
        }
        return result
    }
}
