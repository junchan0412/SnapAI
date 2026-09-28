import Foundation

/// 设置页 keypath 读写:把 SwiftUI `Binding` 里内联的 get/set 抽成可单测的纯函数。
///
/// 界面层零依赖(不引入 ViewInspector 之类),绑定语义因此下沉到 Logic:
/// view 只保留 `Binding(get:set:)` 包装与 commit 策略(`SettingsCommitPolicy`),
/// 「取哪个值、写没写进去、写完是否归一化激活项」由 `SnapAILogicTests` 覆盖。
///
/// 语义与搬出前逐行一致:
/// - 读:目标不存在时回退到默认值(`AIProvider()` / `AIModelEntry(name: "")` / `AIAction()`);
/// - 写:目标不存在时返回 false,view 据此跳过 commit;
/// - 供应商与模型写入后调用 `normalizeActive()`,动作写入不调用。
package enum SettingsPageBinding {
    // MARK: - 供应商

    package static func providerValue<V>(_ settings: AppSettings,
                                         providerID: String,
                                         keyPath: KeyPath<AIProvider, V>) -> V {
        (settings.providers.first(where: { $0.id == providerID }) ?? AIProvider())[keyPath: keyPath]
    }

    @discardableResult
    package static func setProviderValue<V>(_ settings: AppSettings,
                                            providerID: String,
                                            keyPath: WritableKeyPath<AIProvider, V>,
                                            to value: V) -> Bool {
        guard let index = settings.providers.firstIndex(where: { $0.id == providerID }) else { return false }
        settings.providers[index][keyPath: keyPath] = value
        settings.normalizeActive()
        return true
    }

    // MARK: - 模型

    package static func modelValue<V>(_ settings: AppSettings,
                                      providerID: String,
                                      modelName: String,
                                      keyPath: KeyPath<AIModelEntry, V>) -> V {
        guard let provider = settings.providers.first(where: { $0.id == providerID }),
              let model = provider.models.first(where: { $0.name == modelName }) else {
            return AIModelEntry(name: "")[keyPath: keyPath]
        }
        return model[keyPath: keyPath]
    }

    @discardableResult
    package static func setModelValue<V>(_ settings: AppSettings,
                                         providerID: String,
                                         modelName: String,
                                         keyPath: WritableKeyPath<AIModelEntry, V>,
                                         to value: V) -> Bool {
        guard let providerIndex = settings.providers.firstIndex(where: { $0.id == providerID }),
              let modelIndex = settings.providers[providerIndex].models.firstIndex(where: { $0.name == modelName }) else {
            return false
        }
        settings.providers[providerIndex].models[modelIndex][keyPath: keyPath] = value
        settings.normalizeActive()
        return true
    }

    // MARK: - 动作

    package static func actionValue<V>(_ settings: AppSettings,
                                       actionID: String,
                                       keyPath: KeyPath<AIAction, V>) -> V {
        (settings.actions.first(where: { $0.id == actionID }) ?? AIAction())[keyPath: keyPath]
    }

    @discardableResult
    package static func setActionValue<V>(_ settings: AppSettings,
                                          actionID: String,
                                          keyPath: WritableKeyPath<AIAction, V>,
                                          to value: V) -> Bool {
        guard let index = settings.actions.firstIndex(where: { $0.id == actionID }) else { return false }
        settings.actions[index][keyPath: keyPath] = value
        return true
    }
}
