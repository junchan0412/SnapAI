import AppKit
import SnapAILogic

enum MenuCoordinator {
    static func configureShortcut(_ item: NSMenuItem, combo: HotKeyCombo?) {
        guard let combo, !combo.isUnset else { return }
        item.keyEquivalent = combo.keyEquivalent
        item.keyEquivalentModifierMask = combo.nsModifierFlags
    }

    static func modelSwitchMenu(settings: AppSettings,
                                target: AnyObject,
                                action: Selector,
                                settingsTarget: AnyObject? = nil,
                                settingsAction: Selector? = nil) -> NSMenu {
        let sub = NSMenu()
        let providerInputs = settings.providers.map { provider in
            ModelSwitchProviderInput(id: provider.id,
                                     name: provider.name,
                                     isEnabled: provider.isEnabled,
                                     enabledModelNames: provider.enabledModelNames)
        }
        let descriptors = ModelSwitchCommandFactory.descriptors(
            providers: providerInputs,
            activeProviderID: settings.activeProvider?.id,
            activeModel: settings.model
        )
        if descriptors.isEmpty {
            // 无可用配置时提供可点击的「打开设置」入口,而非灰显死路。
            if let settingsTarget, let settingsAction {
                let item = NSMenuItem(title: "无可用配置,点击打开设置…",
                                      action: settingsAction,
                                      keyEquivalent: "")
                item.target = settingsTarget
                sub.addItem(item)
            } else {
                let item = NSMenuItem(title: "无可用配置,请到设置添加", action: nil, keyEquivalent: "")
                item.isEnabled = false
                sub.addItem(item)
            }
            return sub
        }
        for provider in providerInputs where provider.isEnabled {
            let providerDescriptors = descriptors.filter { $0.providerID == provider.id }
            guard let firstDescriptor = providerDescriptors.first else { continue }
            let header = NSMenuItem(title: firstDescriptor.providerName, action: nil, keyEquivalent: "")
            header.isEnabled = false
            // 供应商标题加粗,与模型项视觉区分。
            let headerFont = NSFontManager.shared.convert(
                NSFont.menuBarFont(ofSize: 0),
                toHaveTrait: .boldFontMask
            )
            header.attributedTitle = NSAttributedString(
                string: firstDescriptor.providerName,
                attributes: [.font: headerFont,
                             .foregroundColor: NSColor.labelColor]
            )
            sub.addItem(header)
            for descriptor in providerDescriptors {
                // 用 indentationLevel 取代手动空格缩进,系统会正确对齐。
                let item = NSMenuItem(title: descriptor.title,
                                      action: action,
                                      keyEquivalent: "")
                item.indentationLevel = 1
                item.target = target
                item.representedObject = [
                    "provider": descriptor.providerID,
                    "model": descriptor.modelName
                ]
                if descriptor.systemImage == "checkmark.circle.fill" {
                    item.state = .on
                }
                sub.addItem(item)
            }
            sub.addItem(.separator())
        }
        return sub
    }
}
