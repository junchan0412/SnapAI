import AppKit

enum MenuCoordinator {
    static func configureShortcut(_ item: NSMenuItem, combo: HotKeyCombo?) {
        guard let combo, !combo.isUnset else { return }
        item.keyEquivalent = combo.keyEquivalent
        item.keyEquivalentModifierMask = combo.nsModifierFlags
    }

    static func modelSwitchMenu(settings: AppSettings,
                                target: AnyObject,
                                action: Selector) -> NSMenu {
        let sub = NSMenu()
        let enabledProviders = settings.providers.filter { $0.isEnabled }
        if enabledProviders.isEmpty {
            let item = NSMenuItem(title: "无可用配置,请到设置添加", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
            return sub
        }
        for provider in enabledProviders {
            let names = provider.enabledModelNames
            if names.isEmpty { continue }
            let providerName = MarkdownExportSafety.metadata(provider.name,
                                                             fallback: "未命名供应商",
                                                             maxLength: 80)
            let header = NSMenuItem(title: providerName, action: nil, keyEquivalent: "")
            header.isEnabled = false
            sub.addItem(header)
            for model in names {
                let modelName = MarkdownExportSafety.metadata(model,
                                                              fallback: "未命名模型",
                                                              maxLength: 120)
                let item = NSMenuItem(title: "  \(modelName)",
                                      action: action,
                                      keyEquivalent: "")
                item.target = target
                item.representedObject = ["provider": provider.id, "model": model]
                if provider.id == settings.activeProvider?.id && model == settings.model {
                    item.state = .on
                }
                sub.addItem(item)
            }
            sub.addItem(.separator())
        }
        return sub
    }
}
