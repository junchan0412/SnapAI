import Foundation
import SnapAILogic

private final class CompareFixtureStore: @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [String: StreamFixturePlan] = [:]
    private var bodies: [[String: Any]] = []

    func reset(_ plans: [String: StreamFixturePlan]) {
        lock.lock()
        defer { lock.unlock() }
        self.plans = plans
        bodies = []
    }

    func response(_ request: URLRequest) -> StreamFixturePlan {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        lock.lock()
        defer { lock.unlock() }
        bodies.append(body)
        return plans[body["model"] as? String ?? ""] ?? StreamFixturePlan(status: 500, chunks: [(0, "Unexpected model")])
    }

    func requests() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }
}

private final class CompareFixtureProtocol: URLProtocol {
    static let store = CompareFixtureStore()
    private let queue = DispatchQueue(label: "com.snapai.compare-fixture")
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let plan = Self.store.response(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: plan.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let start = DispatchTime.now()
        for (index, chunk) in plan.chunks.enumerated() {
            queue.asyncAfter(deadline: start + chunk.delay) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let stopped = self.stopped
                self.lock.unlock()
                guard !stopped else { return }
                self.client?.urlProtocol(self, didLoad: Data(chunk.body.utf8))
                if index == plan.chunks.count - 1 { self.client?.urlProtocolDidFinishLoading(self) }
            }
        }
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

@MainActor
func runModelCompareRuntimeTests() async -> [String] {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append("Model compare: " + message) }
    }
    func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(4)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
    }
    func content(_ text: String, done: Bool = true) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": text]]]])
        return "data: \(String(decoding: data, as: UTF8.self))\n\n" + (done ? "data: [DONE]\n\n" : "")
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapAI-Compare-\(UUID().uuidString)")
    let suite = "com.snapai.compare-runtime.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
    let settings = AppSettings()
    settings.persistenceDefaults = defaults
    settings.persistenceHistoryStore = HistoryStore(url: root.appendingPathComponent("history.sqlite"))
    let provider = AIProvider(id: "compare-fixture", name: "Offline compare", baseURL: "https://compare.invalid/v1",
                              apiKey: "fixture", models: [AIModelEntry(name: "gpt-4o"), AIModelEntry(name: "gpt-4o-mini")])
    settings.providers = [provider]
    settings.activeProviderID = provider.id
    settings.activeModel = "gpt-4o"
    settings.secretStoreCache = [provider.id: provider.apiKey]
    settings.autoRouteEnabled = true
    settings.fallbackEnabled = true
    settings.privacyPreviewEnabled = false
    settings.redactionEnabled = false
    settings.iCloudSyncEnabled = false
    let metrics = RoutingMetricsStore(url: root.appendingPathComponent("metrics.json"), saveHandler: { _, _ in })
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CompareFixtureProtocol.self]
    let network = URLSession(configuration: configuration)
    defer { network.invalidateAndCancel() }
    let action = AIAction(name: "Compare fixture", prompt: "{{text}}", saveHistory: false)
    let models = ["gpt-4o", "gpt-4o-mini"]
    func make(_ messages: [ChatMessage] = [ChatMessage(role: .user, content: "same input")]) -> ModelCompareSession {
        let session = ModelCompareSession(settings: settings, action: action, messages: messages,
                                          session: network, metricsStore: metrics)
        session.leftRouteID = session.routes.first(where: { $0.modelName == models[0] }).map(ModelCompareSession.routeID) ?? ""
        session.rightRouteID = session.routes.first(where: { $0.modelName == models[1] }).map(ModelCompareSession.routeID) ?? ""
        return session
    }

    CompareFixtureProtocol.store.reset([
        models[0]: StreamFixturePlan(chunks: [(0.02, content("left answer"))]),
        models[1]: StreamFixturePlan(chunks: [(0.12, content("right answer"))])
    ])
    var input = [ChatMessage(role: .system, content: "system snapshot"),
                 ChatMessage(role: .user, content: "image snapshot", imageData: Data([1, 2, 3]), imageMimeType: "image/jpeg")]
    let pair = make(input)
    input[1].content = "mutated after creation"
    input[1].imageData = nil
    try? await Task.sleep(nanoseconds: 40_000_000)
    check(CompareFixtureProtocol.store.requests().isEmpty && pair.left == nil && pair.right == nil,
          "opening a session sends nothing before explicit start")
    pair.start()
    pair.start()
    await waitUntil { !pair.isRunning }
    check(pair.left?.status == .succeeded && pair.right?.status == .succeeded,
          "both independent requests complete")
    check(pair.left?.output == "left answer" && pair.right?.output == "right answer",
          "each model publishes its own response")
    let bodies = CompareFixtureProtocol.store.requests()
    check(bodies.count == 2 && Set(bodies.compactMap { $0["model"] as? String }) == Set(models),
          "explicit start sends exactly two distinct model requests")
    let payloads = bodies.compactMap { $0["messages"] as? [[String: Any]] }
    check(payloads.count == 2 && payloads.allSatisfy { messages in
        guard messages.count == 2, messages[0]["content"] as? String == "system snapshot",
              let parts = messages[1]["content"] as? [[String: Any]] else { return false }
        return parts.contains { $0["text"] as? String == "image snapshot" } && parts.contains {
            guard let image = $0["image_url"] as? [String: Any], let url = image["url"] as? String else { return false }
            return !url.isEmpty
        }
    }, "both requests preserve the captured messages and image attachment")
    check(pair.left?.firstTokenMilliseconds != nil && pair.right?.firstTokenMilliseconds != nil &&
          pair.left?.finishedAt != nil && pair.right?.finishedAt != nil,
          "each request records its own first response and finish timing")
    await waitUntil { pair.comparison != nil }
    check(pair.comparison?.isIdentical == false, "completed distinct results create a real comparison")
    if let right = pair.right { pair.choose(right) }
    check(pair.selectedRouteID == pair.rightRouteID, "choosing records the selected completed output")
    pair.close()

    CompareFixtureProtocol.store.reset([
        models[0]: StreamFixturePlan(status: 500, chunks: [(0, "fixture failure")]),
        models[1]: StreamFixturePlan(chunks: [(0.1, content("survivor"))])
    ])
    let failed = make()
    failed.start()
    await waitUntil { !failed.isRunning }
    check(failed.left?.status == .failed && failed.left?.errorMessage != nil &&
          failed.right?.status == .succeeded && failed.right?.output == "survivor",
          "a failed side leaves the other request running to success")
    failed.close()

    for closeBoth in [false, true] {
        CompareFixtureProtocol.store.reset(Dictionary(uniqueKeysWithValues: models.map { model in
            (model, StreamFixturePlan(chunks: [(0, content("prefix-" + model, done: false)),
                                              (0.25, content("-late"))]))
        }))
        let cancelled = make()
        cancelled.start()
        await waitUntil { cancelled.left?.output.isEmpty == false && cancelled.right?.output.isEmpty == false }
        if closeBoth { cancelled.close() } else { cancelled.left?.cancel() }
        let leftAtStop = cancelled.left?.output
        let rightAtStop = cancelled.right?.output
        try? await Task.sleep(nanoseconds: 350_000_000)
        check(cancelled.left?.status == .cancelled && cancelled.left?.output == leftAtStop &&
              cancelled.left?.errorMessage == nil, "cancelled side rejects delayed output and completion")
        if closeBoth {
            check(cancelled.right?.status == .cancelled && cancelled.right?.output == rightAtStop &&
                  !cancelled.isRunning && cancelled.comparison == nil && !cancelled.canStart,
                  "closing cancels both sides and prevents late comparison publication or restart")
        } else {
            check(cancelled.right?.status == .succeeded && cancelled.right?.output.hasSuffix("-late") == true,
                  "single-side cancellation does not cancel the other model")
        }
        cancelled.close()
    }
    return failures
}
