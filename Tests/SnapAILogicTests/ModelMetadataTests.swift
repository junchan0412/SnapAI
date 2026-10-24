import Foundation
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func testModelMetadataPersistenceAndSanitization() {
    let oldProvider = try? JSONDecoder().decode(AIProvider.self, from: Data(#"{"name":"Legacy"}"#.utf8))
    expect(oldProvider?.streamUsageEnabled == true, "legacy providers request stream usage by default")
    let strictProvider = AIProvider(name: "Strict compatible", streamUsageEnabled: false)
    if let data = try? JSONEncoder().encode(strictProvider),
       let restored = try? JSONDecoder().decode(AIProvider.self, from: data) {
        expect(!restored.streamUsageEnabled, "the stream usage compatibility override survives a configuration round trip")
    } else {
        expect(false, "stream usage compatibility settings can be encoded and decoded")
    }
    let old = try? JSONDecoder().decode(AIModelEntry.self, from: Data(#"{"name":"old-alias","enabled":false}"#.utf8))
    expect(old?.enabled == false && old?.metadata == ModelMetadataOverrides(),
           "model entries saved before metadata remain readable")
    let metadata = ModelMetadataOverrides(supportsVision: true, supportsReasoning: false,
        contextTokens: 128_000, inputUSDPerMillionTokens: 2.5, outputUSDPerMillionTokens: 10,
        capabilitySource: " https://vendor.test/models ", pricingSource: "报价 2026-10-04")
    var provider = AIProvider(id: "metadata-provider", name: "Alias provider",
        models: [AIModelEntry(name: " alias ", enabled: true, metadata: metadata)])
    let sanitized = AppSettings.sanitizedImportedModels(provider.models)
    expect(sanitized.first?.name == "alias" && sanitized.first?.metadata.supportsVision == true,
           "importing and trimming model names preserves capability metadata")
    expect(sanitized.first?.metadata.capabilitySource == "https://vendor.test/models",
           "capability sources survive import with surrounding whitespace removed")
    provider.models = sanitized
    provider.mergeModels(["alias", "new-model"])
    expect(provider.models[0].metadata == metadata.sanitized && !provider.models[1].enabled,
           "fetching models preserves overrides and leaves new models disabled")
    let settings = AppSettings()
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "alias"
    if let data = settings.exportConfigurationData(),
       let restored = try? JSONDecoder().decode(AppSettings.self, from: data) {
        expect(restored.providers.first?.models.first?.metadata == metadata.sanitized,
               "configuration export and restore preserve capability and price sources")
    } else {
        expect(false, "metadata settings can be exported and decoded")
    }
    let cloudPayload = CloudSettingsPayload(settings: settings)
    if let data = try? JSONEncoder().encode(cloudPayload),
       let restored = try? JSONDecoder().decode(CloudSettingsPayload.self, from: data) {
        expect(restored.providers.first?.models.first?.metadata == metadata.sanitized,
               "iCloud configuration payload preserves model metadata")
    } else {
        expect(false, "metadata iCloud payload round trips")
    }
    let invalid = ModelMetadataOverrides(contextTokens: -1,
        inputUSDPerMillionTokens: .infinity, outputUSDPerMillionTokens: -0.1,
        capabilitySource: " \n ", pricingSource: String(repeating: "x", count: 2_000)).sanitized
    expect(invalid.contextTokens == nil && invalid.inputUSDPerMillionTokens == nil
           && invalid.outputUSDPerMillionTokens == nil && invalid.capabilitySource == nil
           && invalid.pricingSource?.count == 1_000,
           "invalid imported metadata cannot poison context routing or billing")
}

func testModelMetadataRoutesAndPreflightUseProviderOverrides() {
    let capable = AIProvider(id: "capable", name: "Custom", baseURL: "https://model.test/v1", apiKey: "fixture",
        models: [AIModelEntry(name: "same-alias", metadata: ModelMetadataOverrides(
            supportsVision: true, supportsReasoning: true, contextTokens: 200_000))])
    let limited = AIProvider(id: "limited", name: "Custom", baseURL: "https://model.test/v1", apiKey: "fixture",
        models: [AIModelEntry(name: "same-alias", metadata: ModelMetadataOverrides(
            supportsVision: false, supportsReasoning: false, contextTokens: 1_000))])
    let settings = AppSettings()
    settings.providers = [limited, capable]
    settings.activeProviderID = limited.id
    settings.activeModel = "same-alias"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = true
    var action = AIAction()
    action.thinkingMode = true
    let routes = AIRequestRouter.candidates(settings: settings, action: action,
        sourceText: "a", hasImage: true, routingTextCharacterCount: 30_000)
    expect(routes.first?.providerID == capable.id,
           "manual capability overrides promote an arbitrary alias for vision, reasoning and long context")
    expect(routes.first?.capability.supportsVision == true
           && routes.first?.capability.supportsReasoning == true
           && routes.first?.capability.contextTokens == 200_000,
           "route snapshots retain the effective provider-specific model capabilities")
    expect(routes.last?.capability.supportsVision == false,
           "same model and provider names on another provider ID do not share overrides")
    expect(AIRequestPayloadDiagnostic.candidateHardIssueSummary(routes: Array(routes.prefix(1)),
        estimatedTextTokens: 10_000, hasImage: true) == "all-ok",
           "preflight uses the same overridden capabilities as routing")
    expect(AIRequestPayloadDiagnostic.candidateFitIssueSummary(routes: Array(routes.prefix(1)),
        estimatedTextTokens: 10_000, hasImage: true, requiresReasoning: true) == "all-ok",
           "diagnostics do not report inferred capability warnings for overridden aliases")
    settings.privacyPreviewEnabled = false
    settings.redactionEnabled = false
    let compare = ModelCompare.eligibleRoutes(settings: settings, action: action,
        messages: [ChatMessage(role: .user, content: "图表", imageData: Data([1]))])
    expect(compare.count == 1 && compare.first?.providerID == capable.id,
           "comparison candidates also honor manual vision metadata")
    var namedVision = capable
    namedVision.models = [AIModelEntry(name: "gpt-4o", metadata: ModelMetadataOverrides(supportsVision: false))]
    expect(!ModelCapabilityRegistry.capability(for: "gpt-4o", provider: namedVision).supportsVision,
           "explicit false overrides a model name that otherwise implies vision")
}

func testModelMetadataPricesAreExplicitAndProviderScoped() {
    let settings = AppSettings()
    settings.providers = [
        AIProvider(id: "priced", models: [AIModelEntry(name: "alias", metadata: ModelMetadataOverrides(
            inputUSDPerMillionTokens: 2, outputUSDPerMillionTokens: 8, pricingSource: "Contract A"))]),
        AIProvider(id: "unpriced", models: [AIModelEntry(name: "alias")])
    ]
    let pricing = ModelCapabilityRegistry.pricing(providerID: "priced", modelName: "alias", settings: settings)
    expect(pricing?.estimatedCost(inputTokens: 500_000, outputTokens: 250_000) == 3,
           "cost uses independent input and output prices per million tokens")
    expect(pricing?.source == "Contract A", "price source is available to usage reporting")
    expect(ModelCapabilityRegistry.pricing(providerID: "unpriced", modelName: "alias", settings: settings) == nil,
           "an identically named model on a different provider has unknown pricing")
    settings.providers[0].models[0].metadata.outputUSDPerMillionTokens = nil
    expect(ModelCapabilityRegistry.pricing(providerID: "priced", modelName: "alias", settings: settings) == nil,
           "partial pricing must not imply a free missing component")
    settings.providers[0].models[0].metadata.inputUSDPerMillionTokens = 0
    settings.providers[0].models[0].metadata.outputUSDPerMillionTokens = 0
    expect(ModelCapabilityRegistry.pricing(providerID: "priced", modelName: "alias", settings: settings)?
        .estimatedCost(inputTokens: 500_000, outputTokens: 250_000) == 0,
           "explicit zero prices are distinguished from unknown prices")
}
