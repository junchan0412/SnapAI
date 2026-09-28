import Foundation
@testable import SnapAILogic

/// 设置页 keypath 绑定(`SettingsPageBinding`)的覆盖。
///
/// 界面层零依赖(不引入 ViewInspector),所以「取哪个值 / 写没写进去 /
/// 写完是否归一化激活项」这套绑定语义下沉到 Logic 层测,view 只留包装。
func testSettingsPageBindingCoversProviderModelAndActionKeyPaths() {
    let settings = AppSettings()
    settings.providers = [
        AIProvider(id: "p1", name: "甲", models: [AIModelEntry(name: "m1")]),
        AIProvider(id: "p2", name: "乙", models: [AIModelEntry(name: "m1")])
    ]
    settings.activeProviderID = "p1"
    settings.activeModel = "m1"

    // 供应商读:命中目标字段。
    expect(SettingsPageBinding.providerValue(settings, providerID: "p1", keyPath: \.name) == "甲",
           "provider read returns the target provider field")
    // 供应商读:不存在的 id 回退到默认 AIProvider 的字段值,与 UI 初值一致。
    expect(SettingsPageBinding.providerValue(settings, providerID: "missing", keyPath: \.name) == AIProvider().name,
           "provider read falls back to the default provider for an unknown id")
    expect(SettingsPageBinding.providerValue(settings, providerID: "missing", keyPath: \.isEnabled) == AIProvider().isEnabled,
           "provider read fallback keeps default enabled state")

    // 供应商写:命中时只改目标,并归一化激活项。
    expect(SettingsPageBinding.setProviderValue(settings, providerID: "p1", keyPath: \.name, to: "甲改"),
           "provider write hits the target provider")
    expect(settings.providers.first(where: { $0.id == "p1" })?.name == "甲改",
           "provider write persists the new value")
    expect(settings.providers.first(where: { $0.id == "p2" })?.name == "乙",
           "provider write leaves the other provider untouched")
    expect(SettingsPageBinding.setProviderValue(settings, providerID: "p1", keyPath: \.isEnabled, to: false),
           "provider write can disable the active provider")
    expect(settings.activeProviderID == "p2",
           "provider write runs normalizeActive and moves activation to the next enabled provider")

    // 供应商写:不存在的 id 返回 false,view 据此跳过 commit。
    expect(!SettingsPageBinding.setProviderValue(settings, providerID: "missing", keyPath: \.name, to: "x"),
           "provider write misses return false")
    expect(settings.providers.count == 2,
           "provider write miss does not append a new provider")

    // 模型读写:命中、回退、缺失目标不写。
    expect(SettingsPageBinding.modelValue(settings, providerID: "p2", modelName: "m1", keyPath: \.enabled) == true,
           "model read returns the target model field")
    expect(SettingsPageBinding.modelValue(settings, providerID: "p2", modelName: "missing", keyPath: \.enabled)
            == AIModelEntry(name: "").enabled,
           "model read falls back to the default entry for an unknown model")
    expect(SettingsPageBinding.setModelValue(settings, providerID: "p2", modelName: "m1", keyPath: \.enabled, to: false),
           "model write hits the target model")
    expect(settings.providers.first(where: { $0.id == "p2" })?.models.first?.enabled == false,
           "model write persists the new value")
    expect(settings.activeModel == "",
           "model write runs normalizeActive and clears an activation whose only model is disabled")
    expect(!SettingsPageBinding.setModelValue(settings, providerID: "missing", modelName: "m1", keyPath: \.enabled, to: false),
           "model write misses return false for an unknown provider")
    expect(!SettingsPageBinding.setModelValue(settings, providerID: "p2", modelName: "missing", keyPath: \.enabled, to: false),
           "model write misses return false for an unknown model")

    // 动作读写:命中、回退、缺失目标不写(动作写入不触发 normalizeActive)。
    var action = AIAction(name: "甲动作")
    action.id = "a1"
    settings.actions = [action]
    expect(SettingsPageBinding.actionValue(settings, actionID: "a1", keyPath: \.name) == "甲动作",
           "action read returns the target action field")
    expect(SettingsPageBinding.actionValue(settings, actionID: "missing", keyPath: \.name) == AIAction().name,
           "action read falls back to the default action for an unknown id")
    expect(SettingsPageBinding.setActionValue(settings, actionID: "a1", keyPath: \.isEnabled, to: false),
           "action write hits the target action")
    expect(settings.actions.first?.isEnabled == false,
           "action write persists the new value")
    expect(settings.activeProviderID == "p2",
           "action write does not disturb the active provider")
    expect(!SettingsPageBinding.setActionValue(settings, actionID: "missing", keyPath: \.isEnabled, to: false),
           "action write misses return false")
}
