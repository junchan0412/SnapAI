import Foundation

struct ModelSwitchCommandDescriptor: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var providerID: String
    var modelName: String
}

enum ModelSwitchCommandFactory {
    static func descriptors(providers: [AIProvider],
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

    private static func descriptor(provider: AIProvider,
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
