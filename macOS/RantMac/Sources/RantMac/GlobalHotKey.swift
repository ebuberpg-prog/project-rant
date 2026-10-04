import Carbon.HIToolbox
import Foundation

final class GlobalHotKey {
    var onPress: (() -> Void)?
    var onRegistration: ((String?) -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handlerContext: UnsafeMutableRawPointer?

    func register() {
        unregister()
        let context = Unmanaged.passRetained(self).toOpaque()
        handlerContext = context
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard result == noErr, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.onPress?() }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandler
        )
        guard status == noErr else {
            releaseHandlerContext()
            onRegistration?(nil)
            return
        }
        let identifier = EventHotKeyID(signature: OSType(0x52414E54), id: 1)
        let choices: [(UInt32, String)] = [
            (UInt32(cmdKey | optionKey), "⌘⌥ Space"),
            (UInt32(controlKey | optionKey), "⌃⌥ Space")
        ]
        for (modifiers, label) in choices {
            var reference: EventHotKeyRef?
            let registration = RegisterEventHotKey(UInt32(kVK_Space), modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
            if registration == noErr, let reference {
                hotKeyRef = reference
                onRegistration?(label)
                return
            }
        }
        onRegistration?(nil)
        unregister()
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        releaseHandlerContext()
    }

    private func releaseHandlerContext() {
        if let handlerContext {
            Unmanaged<GlobalHotKey>.fromOpaque(handlerContext).release()
            self.handlerContext = nil
        }
    }

    deinit { unregister() }
}
