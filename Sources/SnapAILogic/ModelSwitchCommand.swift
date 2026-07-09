import Foundation

public struct ModelSwitchProviderInput: Equatable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var enabledModelNames: [String]

    public init(id: String,
                name: String,
                isEnabled: Bool,
                enabledModelNames: [String]) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.enabledModelNames = enabledModelNames
    }
}

public struct ModelSwitchCommandDescriptor: Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
    public var providerID: String
    public var modelName: String
}

public enum ModelSwitchCommandFactory {
    public static func descriptors(providers: [ModelSwitchProviderInput],
                                   activeProviderID: String?,
                                   activeModel: String) -> [ModelSwitchCommandDescriptor] {
        var usedIDs = Set<String>()
        return providers
            .filter(\.isEnabled)
            .flatMap { provider in
                provider.enabledModelNames.map { model in
                    descriptor(provider: provider,
                               model: model,
                               isCurrent: provider.id == activeProviderID && model == activeModel,
                               usedIDs: &usedIDs)
                }
            }
    }

    private static func descriptor(provider: ModelSwitchProviderInput,
                                   model: String,
                                   isCurrent: Bool,
                                   usedIDs: inout Set<String>) -> ModelSwitchCommandDescriptor {
        let providerName = MarkdownExportSafety.metadata(provider.name,
                                                         fallback: "未命名供应商",
                                                         maxLength: 80)
        let modelTitle = MarkdownExportSafety.metadata(model,
                                                       fallback: "未命名模型",
                                                       maxLength: 120)
        return ModelSwitchCommandDescriptor(
            id: descriptorID(providerID: provider.id, model: model, usedIDs: &usedIDs),
            title: modelTitle,
            subtitle: isCurrent ? "当前模型 - \(providerName)" : "切换模型 - \(providerName)",
            systemImage: isCurrent ? "checkmark.circle.fill" : "cpu",
            keywords: MarkdownExportSafety.keywords([
                "model provider ai switch 模型 供应商 切换",
                providerName,
                modelTitle
            ]),
            providerID: provider.id,
            modelName: model
        )
    }

    private static func descriptorID(providerID: String, model: String, usedIDs: inout Set<String>) -> String {
        CommandIdentifier.unique(prefix: "model",
                                 values: [providerID, model],
                                 usedIDs: &usedIDs)
    }
}
