import Foundation
import SnapAILogic

@MainActor
func runConversationRuntimeTests() async -> [String] {
    var failures: [String] = []
    func check(_ value: Bool, _ message: String) {
        if !value { failures.append("Conversation: " + message) }
    }
    func wait(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        check(condition(), "request completes")
    }
    func response(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": text]]]])
        return "data: \(String(decoding: data, as: UTF8.self))\n\ndata: [DONE]\n\n"
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapAI-ConversationRuntime-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let suite = "com.snapai.conversation-runtime.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings()
    settings.persistenceDefaults = defaults
    settings.persistenceHistoryStore = HistoryStore(url: root.appendingPathComponent("history.sqlite"))
    settings.persistenceConversationStore = ConversationStore(url: root.appendingPathComponent("sessions.sqlite"))
    let provider = AIProvider(id: "conversation-fixture", name: "Fixture", baseURL: "https://snapai-app.test/v1",
        apiKey: "fixture-key", models: [AIModelEntry(name: "fixture-model")])
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "fixture-model"
    settings.secretStoreCache = [provider.id: provider.apiKey]
    settings.typewriterSpeed = .off
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = false
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StreamFixtureProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let vm = ResultViewModel(settings: settings, session: session)
    let action = AIAction(name: "Conversation fixture", prompt: "{{text}}", saveHistory: true)
    StreamFixtureProtocol.store.reset([(200, response("first answer")), (200, response("second answer")),
                                       (200, response("branch answer")), (200, response("resend answer"))])
    let image = Data([1, 2, 3, 4])
    vm.start(text: "OCR original", action: action, retainedImageData: image, retainedImageMimeType: "image/jpeg")
    await wait { !vm.isGenerating }
    vm.followUp = "second question"
    vm.sendFollowUp()
    await wait { !vm.isGenerating }
    guard let original = vm.conversationSession else { return failures + ["Conversation missing"] }
    check(original.messages.filter { $0.role != .system }.count == 4, "all turns retained")
    check(original.sourceImageData == image && original.sourceImageWasSubmitted == false, "OCR-only image retained separately")
    do {
        let restored = try settings.persistenceConversationStore.load(id: original.id).get()!
        let requestCount = StreamFixtureProtocol.store.requests().count
        var writes = 0
        vm.onReplace = { _, _ in writes += 1 }
        vm.onAppend = { _ in writes += 1 }
        vm.restoreConversation(restored)
        check(vm.completeText == "second answer" && StreamFixtureProtocol.store.requests().count == requestCount,
              "restore displays saved output without any network request")
        check(vm.charCount == "second answer".count, "restored character count matches saved output")
        vm.replaceOriginal()
        vm.appendToDocument()
        check(writes == 0, "restore cannot write into a stale document")
        let firstAnswer = original.messages.first { $0.role == .assistant }!
        vm.branchConversation(through: firstAnswer.id)
        check(vm.conversationSession?.parentSessionID == original.id && vm.completeText == "first answer", "branch opens selected prefix")
        vm.compressConversation(through: firstAnswer.id, summary: "confirmed summary")
        vm.followUp = "branch question"
        vm.sendFollowUp()
        await wait { !vm.isGenerating }
        let body = try JSONSerialization.jsonObject(with: StreamFixtureProtocol.store.requests().last!.body) as! [String: Any]
        let payload = body["messages"] as! [[String: Any]]
        let contents = payload.compactMap { $0["content"] as? String }.joined(separator: "\n")
        check(contents.contains("confirmed summary") && contents.contains("branch question") && !contents.contains("OCR original"),
              "compressed follow-up sends only approved summary and new question")
        check(vm.conversationSession?.messages.first(where: { $0.role == .user })?.content == "OCR original", "compression preserves original turns")
        check((try settings.persistenceConversationStore.load(id: original.id).get()) == original, "branch does not modify original")
        vm.disableConversationCompression()
        check(vm.conversationSession?.activeCompression == nil, "compression is reversible")
        vm.resendEdited()
        await wait { !vm.isGenerating }
        let resend = try JSONSerialization.jsonObject(with: StreamFixtureProtocol.store.requests().last!.body) as! [String: Any]
        check((resend["messages"] as? [[String: Any]])?.last?["content"] is String, "OCR-only resend does not upload retained image")
        settings.historyContentStorage = .metadataOnly
        check(settings.save(), "privacy change persists")
        check((try settings.persistenceConversationStore.list(limit: 50).get()).isEmpty, "metadata-only clears sessions and image BLOBs")
        settings.historyContentStorage = .full
        _ = vm.persistConversation()
        check(settings.clearHistory(), "clear all history succeeds")
        check((try settings.persistenceConversationStore.list(limit: 50).get()).isEmpty, "clear history also removes sessions")
    } catch { failures.append("Conversation runtime: \(error)") }
    return failures
}
