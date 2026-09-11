import Carbon
import Foundation
import PDFQuoteCollectorCore

@MainActor
final class GlobalShortcutRegistrar {
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    func register(_ configuration: ShortcutConfiguration, action: @escaping @MainActor () -> Void) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let readStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard readStatus == noErr, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
                let registrar = Unmanaged<GlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { registrar.action?() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandlerReference
        )
        guard status == noErr else { throw ShortcutError.registrationFailed(status) }

        guard let keyCode = Self.keyCodes[configuration.key.uppercased()] else {
            unregister()
            throw ShortcutError.invalidKey
        }
        let identifier = EventHotKeyID(signature: OSType(0x50514343), id: 1) // PQCC
        var modifiers: UInt32 = 0
        if configuration.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if configuration.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if configuration.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if configuration.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registerStatus == noErr else {
            unregister()
            throw ShortcutError.registrationFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        if let eventHandlerReference { RemoveEventHandler(eventHandlerReference) }
        hotKeyReference = nil
        eventHandlerReference = nil
        action = nil
    }

    enum ShortcutError: LocalizedError {
        case invalidKey
        case registrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidKey:
                return "The OCR shortcut key must be one letter A–Z."
            case .registrationFailed(let status):
                return "Could not register the OCR shortcut (error \(status)). It may be in use by another app."
            }
        }
    }

    private static let keyCodes: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z)
    ]
}
