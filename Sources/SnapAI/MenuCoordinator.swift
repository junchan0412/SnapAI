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
                                action: Selector) -> NSMenu {
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
            let item = NSMenuItem(title: "无可用配置,请到设置添加", action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
            return sub
        }
        for provider in providerInputs where provider.isEnabled {
            let providerDescriptors = descriptors.filter { $0.providerID == provider.id }
            guard let firstDescriptor = providerDescriptors.first else { continue }
            let header = NSMenuItem(title: firstDescriptor.providerName, action: nil, keyEquivalent: "")
            header.isEnabled = false
            sub.addItem(header)
            for descriptor in providerDescriptors {
                let item = NSMenuItem(title: "  \(descriptor.title)",
                                      action: action,
                                      keyEquivalent: "")
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
