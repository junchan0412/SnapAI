import Foundation

final class HotKeyCoordinator {
    typealias RegisterHotKey = (_ combo: HotKeyCombo, _ handler: @escaping () -> Void) -> UInt32?
    typealias UnregisterAll = () -> Void

    func registerAll(settings: AppSettings,
                     actionHandler: @escaping (String) -> Void,
                     quickPanelHandler: @escaping () -> Void,
                     registerHotKey: RegisterHotKey = { combo, handler in
                         HotKeyManager.shared.register(combo, handler: handler)
                     },
                     unregisterAll: UnregisterAll = {
                         HotKeyManager.shared.unregisterAll()
                     },
                     logFailures: Bool = true) -> [String] {
        unregisterAll()
        var failures: [String] = []
        var used: [HotKeyCombo: String] = [:]

        func register(_ combo: HotKeyCombo,
                      label: String,
                      handler: @escaping () -> Void) {
            guard Self.shouldRegister(combo) else { return }
            if let existing = used[combo] {
                failures.append(Self.conflictMessage(label: label,
                                                     existingLabel: existing,
                                                     combo: combo))
                return
            }
            used[combo] = label
            if registerHotKey(combo, handler) == nil {
                failures.append(Self.registrationFailureMessage(label: label,
                                                               combo: combo))
            }
        }

        for action in settings.enabledActions {
            guard let hotKey = action.hotKey else { continue }
            let actionID = action.id
            register(hotKey, label: "动作「\(action.name)」") {
                actionHandler(actionID)
            }
        }

        register(settings.quickPanelHotKey, label: "快捷提问面板") {
            quickPanelHandler()
        }

        if logFailures, !failures.isEmpty {
            NSLog("SnapAI: 快捷键注册异常 - \(failures.joined(separator: "; "))")
        }
        return failures
    }

    static func shouldRegister(_ combo: HotKeyCombo) -> Bool {
        !combo.isUnset
    }

    static func conflictMessage(label: String,
                                existingLabel: String,
                                combo: HotKeyCombo) -> String {
        "\(label) 与 \(existingLabel) 冲突: \(combo.displayString)"
    }

    static func registrationFailureMessage(label: String,
                                           combo: HotKeyCombo) -> String {
        "\(label) 注册失败: \(combo.displayString)"
    }
}
