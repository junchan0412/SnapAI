import Carbon.HIToolbox
import AppKit

/// 使用 Carbon 的 RegisterEventHotKey 注册系统级全局快捷键。
/// 相比 CGEventTap,这种方式开销极低、不需要轮询、也不要求辅助功能权限即可注册。
final class HotKeyManager {
    static let shared = HotKeyManager()

    private struct Registration {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {
        installHandler()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData = userData, let event = event else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            if status == noErr {
                manager.fire(id: hkID.id)
            }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    private func fire(id: UInt32) {
        if let reg = registrations[id] {
            // 主线程执行 UI 相关逻辑
            DispatchQueue.main.async { reg.handler() }
        }
    }

    /// 注册一个快捷键。返回内部 id;重复注册前请先 unregisterAll。
    @discardableResult
    func register(_ combo: HotKeyCombo, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1

        let signature: OSType = 0x53_4E_41_49 // 'SNAI'
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode,
                                         combo.modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref = ref else {
            NSLog("SnapAI: 注册快捷键失败 status=\(status)")
            return nil
        }
        registrations[id] = Registration(ref: ref, handler: handler)
        return id
    }

    func unregisterAll() {
        for (_, reg) in registrations {
            UnregisterEventHotKey(reg.ref)
        }
        registrations.removeAll()
    }
}
