import AppKit
import Foundation
import SnapAILogic

@MainActor
func runAutomationActionRuntimeTests() async -> [String] {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append("Shortcuts: " + message) }
    }
    func content(_ text: String, done: Bool = true) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": text]]]])
        return "data: \(String(decoding: data, as: UTF8.self))\n\n" + (done ? "data: [DONE]\n\n" : "")
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapAI-Shortcuts-\(UUID().uuidString)")
    let suite = "com.snapai.shortcuts-runtime.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    let settings = AppSettings()
    settings.persistenceDefaults = defaults
    settings.persistenceHistoryStore = HistoryStore(url: root.appendingPathComponent("history.sqlite"))
    let provider = AIProvider(id: "shortcuts-fixture", name: "Offline Shortcuts",
                              baseURL: "https://shortcuts.invalid/v1", apiKey: "fixture",
                              models: [AIModelEntry(name: "gpt-4o-mini")])
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o-mini"
    settings.secretStoreCache = [provider.id: provider.apiKey]
    settings.typewriterSpeed = .slow
    settings.autoRouteEnabled = false
    settings.fallbackEnabled = false
    settings.privacyPreviewEnabled = false
    settings.redactionEnabled = false
    settings.iCloudSyncEnabled = false
    let action = AIAction(name: "Shortcuts fixture", prompt: "{{text}}", replaceByDefault: true, saveHistory: false)
    settings.actions = [action]
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StreamFixtureProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    func prepared(_ text: String, _ action: AIAction) -> PrivacyPreparedSubmission? {
        .passthrough(text: text, saveHistoryEnabled: action.saveHistory,
                     historyContentStorage: settings.historyContentStorage)
    }
    func execute(timeout: TimeInterval = 2, text: String = "fixture input",
                 executingAction: AIAction? = nil) async -> AutomationActionResult {
        do {
            let output = try await AutomationActionExecution(settings: settings, session: session)
                .run(text: text, action: executingAction ?? action, timeout: timeout, prepareSubmission: prepared)
            return AutomationActionResult(text: output)
        } catch { return AutomationActionResult(error: error) }
    }

    let answer = String(repeating: "真正可供下一步使用的正文。", count: 100)
    StreamFixtureProtocol.store.resetPlans([StreamFixturePlan(chunks: [(0.05, content(answer))])])
    let successStart = Date()
    let success = await execute()
    check(success.status == "succeeded" && success.text == answer && success.error == nil,
          "returns the complete AI body rather than a submission acknowledgement")
    check(Date().timeIntervalSince(successStart) < 1,
          "completion does not wait for the slow typewriter presentation")
    check(settings.actionUsageCounts[action.name] == 1 && settings.history.isEmpty,
          "successful execution records usage once and respects disabled history")
    do {
        let decoded = try JSONDecoder().decode(AutomationActionResult.self, from: Data(success.json().utf8))
        check(decoded.status == "succeeded" && decoded.text == answer,
              "JSON output preserves the exact body for Shortcuts dictionary actions")
    } catch { failures.append("Shortcuts: success JSON cannot be decoded") }

    StreamFixtureProtocol.store.reset([(500, "fixture unavailable")])
    let failed = await execute()
    check(failed.status == "failed" && failed.text.isEmpty && failed.error?.code == "request_failed",
          "HTTP failure returns a structured failure without claiming completed text")
    check(settings.actionUsageCounts[action.name] == 1, "failed requests do not record success usage")

    StreamFixtureProtocol.store.reset([(200, "data: [DONE]\n\n")])
    let empty = await execute()
    check(empty.status == "failed" && empty.text.isEmpty,
          "an empty completed stream is not reported as successful")

    StreamFixtureProtocol.store.resetPlans([
        StreamFixturePlan(chunks: [(0, content("partial", done: false)), (0.3, content("late"))])
    ])
    let timeout = await execute(timeout: 0.04)
    check(timeout.error?.code == "timed_out" && timeout.text.isEmpty,
          "timeout stops the request and returns an actionable error rather than partial success")
    try? await Task.sleep(for: .milliseconds(350))
    check(settings.actionUsageCounts[action.name] == 1,
          "late response after timeout cannot record a completed request")

    StreamFixtureProtocol.store.resetPlans([
        StreamFixturePlan(chunks: [(0, content("partial", done: false)), (0.3, content("late"))])
    ])
    let cancelledTask = Task { await execute() }
    let requestDeadline = Date().addingTimeInterval(2)
    while StreamFixtureProtocol.store.requests().isEmpty, Date() < requestDeadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
    cancelledTask.cancel()
    let cancelled = await cancelledTask.value
    check(cancelled.error?.code == "cancelled" && cancelled.text.isEmpty,
          "Task cancellation resumes the caller with the cancelled code")
    try? await Task.sleep(for: .milliseconds(350))
    check(settings.actionUsageCounts[action.name] == 1,
          "cancelled requests ignore delayed success and do not count usage")

    StreamFixtureProtocol.store.resetPlans([])
    var preparationCount = 0
    let preCancelled = Task { @MainActor in
        do {
            _ = try await AutomationActionExecution(settings: settings, session: session)
                .run(text: "fixture", action: action) { text, action in
                    preparationCount += 1
                    return prepared(text, action)
                }
            return "unexpected success"
        } catch { return SnapAIIntentError.normalized(error).code }
    }
    preCancelled.cancel()
    let preCancelledCode = await preCancelled.value
    check(preCancelledCode == "cancelled" && preparationCount == 0 && StreamFixtureProtocol.store.requests().isEmpty,
          "cancellation before execution does not preview or send a request")

    do {
        _ = try await AutomationActionExecution(settings: settings, session: session)
            .run(text: "fixture", action: action) { _, _ in preparationCount += 1; return nil }
        failures.append("Shortcuts: rejected privacy confirmation unexpectedly succeeded")
    } catch {
        check(SnapAIIntentError.normalized(error).code == "privacy_cancelled" && preparationCount == 1 &&
              StreamFixtureProtocol.store.requests().isEmpty,
              "privacy rejection runs before networking and returns a distinct error")
    }

    settings.providers = []
    let unavailable = await execute()
    check(unavailable.error?.code == "request_failed" && StreamFixtureProtocol.store.requests().isEmpty,
          "synchronous route unavailability resumes the waiter without networking or hanging")
    settings.providers = [provider]

    settings.redactionEnabled = true
    let host = AppDelegate(settings: settings, launchSmokeDirectory: root, launchSmokeToken: "fixture")
    host.submissionPipeline = SubmissionPipeline(host: host)
    let sensitive = "联系 analyst@example.invalid"
    let previousSystemPrompt = settings.systemPrompt
    settings.systemPrompt = "系统 system@example.invalid"
    var templatedAction = action
    templatedAction.prompt = "模板 template@example.invalid: {{text}}"
    var approvedMessages: [ChatMessage] = []
    StreamFixtureProtocol.store.reset([(200, content("redacted answer"))])
    do {
        _ = try await AutomationActionExecution(settings: settings, session: session)
            .run(text: sensitive, action: templatedAction) { text, action in
                let prepared = host.prepareTextForSubmission(text, action: action, imageData: nil)
                approvedMessages = prepared?.messages ?? []
                settings.systemPrompt = "确认后改变的未授权上下文 changed@example.invalid"
                return prepared
            }
        let requests = StreamFixtureProtocol.store.requests()
        let bodies = requests.map { String(decoding: $0.body, as: UTF8.self) }
        check(bodies.count == 1 && !bodies[0].contains("@example.invalid") && bodies[0].contains("联系"),
              "the real submission pipeline redacts source, system and action-template content in the actual payload")
        let object = requests.first.flatMap { try? JSONSerialization.jsonObject(with: $0.body) as? [String: Any] }
        let sentMessages = object?["messages"] as? [[String: String]]
        check(!approvedMessages.isEmpty && sentMessages == approvedMessages.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }, "automation sends the exact approved message snapshot despite later configuration changes")
    } catch { failures.append("Shortcuts: redacted submission failed: \(error.localizedDescription)") }
    settings.systemPrompt = previousSystemPrompt

    let local = AIProvider(id: "shortcuts-local", name: "Local fixture", baseURL: "http://localhost:11434/v1",
                           apiKey: "local-fixture", models: [AIModelEntry(name: "llama3.2")])
    settings.providers = [provider, local]
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = true
    settings.privacyPreviewEnabled = true
    settings.historyContentStorage = .metadataOnly
    check(AIRequestRouter.providerReadiness(local).isReady && settings.prefersLocalModelRoutes,
          "local-first fixture has a request-ready local route and privacy routing enabled")
    StreamFixtureProtocol.store.reset([(500, "local fixture failed"), (200, content("cloud must not run"))])
    let localFailure = await execute()
    let routes = StreamFixtureProtocol.store.requests()
    check(localFailure.status == "failed" && routes.count == 1 && routes.first?.url.contains("localhost") == true,
          "local-first requests cannot silently fall back to the cloud without confirmation; " +
          "status=\(localFailure.status), error=\(localFailure.error?.code ?? "none"): \(localFailure.error?.message ?? "none"), " +
          "requests=\(routes.map(\.url)), actionProvider=\(action.providerID ?? "nil"), actionModel=\(action.modelOverride ?? "nil")")

    var boundAction = action
    boundAction.providerID = provider.id
    boundAction.modelOverride = provider.enabledModelNames.first
    StreamFixtureProtocol.store.reset([(500, "local fixture failed"), (200, content("cloud must not run"))])
    let boundFailure = await execute(executingAction: boundAction)
    let boundRequests = StreamFixtureProtocol.store.requests()
    check(boundFailure.status == "failed" && boundRequests.count == 1 &&
          boundRequests.first?.url.contains("localhost") == true,
          "an action-bound cloud model does not bypass local-first fallback confirmation")

    for fallbackEnabled in [true, false] {
        settings.fallbackEnabled = fallbackEnabled
        StreamFixtureProtocol.store.reset([(200, content("cloud must not run"))])
        let imageVM = ResultViewModel(settings: settings, session: session)
        imageVM.start(text: "image fixture", action: action, imageData: Data([1]))
        check(!imageVM.isGenerating && imageVM.errorMessage?.contains("发送到云端前需要确认") == true &&
              imageVM.requestDiagnostics?.requestRecoveryCode == "fallback-cloud-confirmation-required" &&
              StreamFixtureProtocol.store.requests().isEmpty,
              "an incompatible local image model blocks cloud preflight before networking, fallback=\(fallbackEnabled)")
    }
    settings.fallbackEnabled = true

    var shortContextLocal = local
    shortContextLocal.models[0].metadata.contextTokens = 1
    settings.providers = [provider, shortContextLocal]
    StreamFixtureProtocol.store.reset([(200, content("cloud must not run"))])
    let contextFailure = await execute(text: "A local model cannot fit this request.")
    check(contextFailure.status == "failed" && StreamFixtureProtocol.store.requests().isEmpty,
          "context preflight cannot silently send a local-first request to the cloud")

    var secondLocal = shortContextLocal
    secondLocal.id = "shortcuts-second-local"
    settings.providers = [provider, local, secondLocal]
    StreamFixtureProtocol.store.reset([(500, "first local failed"), (200, content("cloud must not run"))])
    let skippedFallbackFailure = await execute()
    let skippedFallbackRequests = StreamFixtureProtocol.store.requests()
    check(skippedFallbackFailure.status == "failed" && skippedFallbackRequests.count == 1 &&
          skippedFallbackRequests.first?.url.contains("localhost") == true,
          "failure followed by an incompatible local fallback still blocks the later cloud route")

    settings.providers = [provider, local]
    let preparation = ResultRequestPreparationCoordinator(settings: settings).prepare(
        ResultRequestPreparationInput(action: action, sourceText: "fixture",
            history: [ChatMessage(role: .user, content: "fixture")], explicitHasImage: false,
            captureMethod: nil, sourceContext: nil, submissionPrivacy: nil))
    if case .ready(let request) = preparation,
       let localIndex = request.routes.firstIndex(where: \.isLocalEndpoint) {
        settings.providers[1].baseURL = "https://changed-endpoint.invalid/v1"
        let attempt = ResultRouteAttemptCoordinator(settings: settings).prepare(
            index: localIndex, routes: request.routes, diagnostics: request.diagnostics)
        if case .unavailable(let diagnostics, _) = attempt {
            check(diagnostics.requestRecoveryCode == "fallback-cloud-confirmation-required",
                  "the final route check uses the actual configured endpoint")
        } else {
            failures.append("Shortcuts: an endpoint changed from local to cloud bypassed confirmation")
        }
    } else {
        failures.append("Shortcuts: local endpoint change fixture could not prepare its route")
    }

    settings.providers = [provider, local]
    settings.autoRouteEnabled = false
    StreamFixtureProtocol.store.reset([(200, content("explicit cloud answer"))])
    let manualCloud = await execute()
    check(manualCloud.status == "succeeded" && manualCloud.text == "explicit cloud answer" &&
          StreamFixtureProtocol.store.requests().first?.url.contains("shortcuts.invalid") == true,
          "turning off auto routing preserves an explicitly selected cloud model")
    settings.autoRouteEnabled = true
    var disabledLocal = local
    disabledLocal.isEnabled = false
    var unreadyLocal = local
    unreadyLocal.apiKey = ""
    for providers in [[provider], [provider, disabledLocal], [provider, unreadyLocal]] {
        settings.providers = providers
        StreamFixtureProtocol.store.reset([(200, content("cloud must not run"))])
        let cloudOnly = await execute()
        check(cloudOnly.status == "failed" && cloudOnly.error?.message.contains("发送到云端前需要确认") == true &&
              StreamFixtureProtocol.store.requests().isEmpty,
              "privacy mode blocks cloud when local providers are absent, disabled or missing an API key")
    }

    do {
        let error = SnapAIIntentError.timedOut
        let decoded = try JSONDecoder().decode(AutomationActionResult.self,
                                              from: Data(AutomationActionResult(error: error).json().utf8))
        let nsError = error as NSError
        check(decoded.status == "failed" && decoded.text.isEmpty && decoded.error?.code == "timed_out" &&
              nsError.domain == SnapAIIntentError.errorDomain && nsError.userInfo["code"] as? String == "timed_out",
              "JSON and thrown NSError expose the same stable error code")
    } catch { failures.append("Shortcuts: error JSON cannot be decoded") }
    return failures
}
