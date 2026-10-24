import Foundation
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func testModelCompareRoutesRespectPrivacyAndImageCapabilities() {
    let settings = AppSettings()
    let cloud = AIProvider(name: "Cloud", apiProtocol: .openAI,
                           baseURL: "https://compare.test/v1", apiKey: "fixture",
                           models: [AIModelEntry(name: "gpt-4o"), AIModelEntry(name: "gpt-4o-mini")])
    let local = AIProvider(name: "Local", apiProtocol: .openAI,
                           baseURL: "http://localhost:11434/v1", apiKey: "ollama",
                           models: [AIModelEntry(name: "llama3.1"), AIModelEntry(name: "qwen2.5")])
    settings.providers = [cloud, local]
    settings.activeProviderID = cloud.id
    settings.activeModel = "gpt-4o"
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = true
    settings.privacyPreviewEnabled = false
    settings.redactionEnabled = false
    let messages = [ChatMessage(role: .user, content: "hello")]
    let routes = ModelCompare.eligibleRoutes(settings: settings, action: AIAction(), messages: messages)
    expect(routes.contains { $0.providerID == cloud.id }, "comparison includes ready cloud routes in cloud mode")
    expect(Set(routes.map(\.id)).count == routes.count, "comparison candidates have distinct routes")

    settings.applyWorkMode(.privacy)
    let privateRoutes = ModelCompare.eligibleRoutes(settings: settings, action: AIAction(), messages: messages)
    expect(privateRoutes.count == 2 && privateRoutes.allSatisfy(\.isLocalEndpoint),
           "privacy comparison never silently includes a cloud route")
    settings.providers[1].apiKey = ""
    let noPrivateRoutes = ModelCompare.eligibleRoutes(settings: settings, action: AIAction(), messages: messages)
    expect(noPrivateRoutes.isEmpty, "privacy comparison refuses cloud fallback when all local routes are unavailable")
    settings.providers[1].apiKey = local.apiKey

    settings.privacyPreviewEnabled = false
    settings.redactionEnabled = false
    let imageRoutes = ModelCompare.eligibleRoutes(settings: settings, action: AIAction(),
        messages: [ChatMessage(role: .user, content: "describe", imageData: Data([1]))])
    expect(!imageRoutes.isEmpty && imageRoutes.allSatisfy {
        AIRequestRouter.modelSupportsImageInput(modelName: $0.modelName, providerName: $0.providerName)
    }, "image comparison excludes text-only routes without stripping attachments")

    settings.providers[0].apiKey = ""
    let unavailable = ModelCompare.eligibleRoutes(settings: settings, action: AIAction(), messages: messages)
    expect(!unavailable.contains { $0.providerID == cloud.id }, "comparison excludes a provider without required credentials")
}
