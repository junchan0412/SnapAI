import Foundation
import Combine
import SnapAILogic

@MainActor
final class ModelCompareRequest: ObservableObject {
    enum Status: String {
        case pending = "等待开始"
        case running = "正在生成"
        case succeeded = "已完成"
        case failed = "请求失败"
        case cancelled = "已停止"
    }

    let route: AIRequestRoute
    @Published private(set) var status: Status = .pending
    @Published private(set) var output = ""
    @Published private(set) var thinking = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var firstTokenMilliseconds: Int?
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?
    var onFinished: (() -> Void)?

    private let client: AIClient
    private let metricsStore: RoutingMetricsStore
    private let pricing: ModelPricing?
    private var accumulator = StreamingAccumulator()
    private var publication: DispatchWorkItem?
    private var generation = UUID()

    init(route: AIRequestRoute,
         settings: AppSettings,
         session: URLSession = .shared,
         metricsStore: RoutingMetricsStore = .shared) {
        self.route = route
        client = AIClient(settings: settings, session: session)
        self.metricsStore = metricsStore
        self.pricing = ModelCapabilityRegistry.pricing(providerID: route.providerID, modelName: route.modelName, settings: settings)
    }

    var title: String { "\(route.diagnosticProviderName) / \(route.diagnosticModelName)" }
    var isRunning: Bool { status == .running }
    var canChoose: Bool {
        !isRunning && status != .pending && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (finishedAt ?? date).timeIntervalSince(startedAt))
    }

    func start(messages: [ChatMessage], action: AIAction) {
        guard status == .pending else { return }
        startedAt = Date()
        status = .running
        let generation = generation
        client.stream(messages: messages, action: action) { [weak self] token in
            guard let self, self.generation == generation, self.isRunning else { return }
            self.recordFirstToken()
            self.accumulator.appendContentToken(token, extractsThinkTags: action.thinkingMode)
            self.schedulePublication()
        } onThinking: { [weak self] text in
            guard let self, self.generation == generation, self.isRunning else { return }
            self.recordFirstToken()
            self.accumulator.appendExternalThinking(text)
            self.schedulePublication()
        } onComplete: { [weak self] error in
            guard let self, self.generation == generation, self.isRunning else { return }
            self.accumulator.finish()
            self.publish()
            self.finishedAt = Date()
            let error = error ?? (self.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AIStreamDecodingError.emptyResponse : nil)
            let milliseconds = Int(self.elapsed() * 1_000)
            self.metricsStore.recordUsage(route: self.route, usage: self.client.latestUsage, pricing: self.pricing,
                firstTokenMilliseconds: self.firstTokenMilliseconds, networkMilliseconds: milliseconds)
            if let error {
                let message = SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription)
                self.errorMessage = message
                self.status = .failed
                self.metricsStore.recordFailure(route: self.route,
                                                elapsedMilliseconds: milliseconds,
                                                firstTokenMilliseconds: self.firstTokenMilliseconds,
                                                reason: message)
            } else {
                self.status = .succeeded
                self.metricsStore.recordSuccess(route: self.route,
                                                elapsedMilliseconds: milliseconds,
                                                firstTokenMilliseconds: self.firstTokenMilliseconds)
            }
            self.onFinished?()
        }
    }

    func cancel() {
        guard isRunning else { return }
        generation = UUID()
        client.cancel()
        accumulator.finish()
        publish()
        finishedAt = Date()
        status = .cancelled
        metricsStore.recordUsage(route: route, usage: client.latestUsage, pricing: pricing,
            firstTokenMilliseconds: firstTokenMilliseconds, networkMilliseconds: Int(elapsed() * 1_000))
        onFinished?()
    }

    private func recordFirstToken() {
        if firstTokenMilliseconds == nil { firstTokenMilliseconds = Int(elapsed() * 1_000) }
    }

    private func schedulePublication() {
        guard publication == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.publish() }
        publication = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    private func publish() {
        publication?.cancel()
        publication = nil
        if output != accumulator.outputText { output = accumulator.outputText }
        if thinking != accumulator.thinkingText { thinking = accumulator.thinkingText }
    }
}

@MainActor
final class ModelCompareSession: ObservableObject {
    let messages: [ChatMessage]
    let action: AIAction
    let routes: [AIRequestRoute]
    let localOnly: Bool
    let redactionEnabled: Bool
    @Published var leftRouteID: String
    @Published var rightRouteID: String
    @Published private(set) var left: ModelCompareRequest?
    @Published private(set) var right: ModelCompareRequest?
    @Published private(set) var hasStarted = false
    @Published private(set) var isRunning = false
    @Published private(set) var isComparing = false
    @Published private(set) var comparison: ModelCompare.Comparison?
    @Published private(set) var selectedRouteID: String?
    @Published private(set) var preparationError: String?

    private let redactionRules: [PrivacyRedactionRule]
    private let settings: AppSettings
    private let session: URLSession
    private let metricsStore: RoutingMetricsStore
    private var closed = false
    private var comparisonGeneration = UUID()

    init(settings: AppSettings,
         action: AIAction,
         messages: [ChatMessage],
         session: URLSession = .shared,
         metricsStore: RoutingMetricsStore = .shared) {
        self.settings = settings
        self.action = action
        self.session = session
        self.metricsStore = metricsStore
        localOnly = settings.prefersLocalModelRoutes
        redactionEnabled = settings.redactionEnabled
        redactionRules = settings.redactionRules
        self.messages = messages.map { message in
            var copy = message
            if settings.redactionEnabled {
                copy.content = PrivacyFilter.preview(text: message.content, rules: settings.redactionRules).output
            }
            return copy
        }
        routes = ModelCompare.eligibleRoutes(settings: settings,
                                             action: action,
                                             messages: self.messages,
                                             routingMetrics: metricsStore.snapshot())
        leftRouteID = routes.first.map(Self.routeID) ?? ""
        rightRouteID = routes.dropFirst().first.map(Self.routeID) ?? ""
    }

    static func routeID(_ route: AIRequestRoute) -> String {
        RoutePerformanceRecord.id(providerID: route.providerID, modelName: route.modelName)
    }

    var canStart: Bool {
        !closed && !hasStarted && !messages.isEmpty && routes.count >= 2 &&
        !leftRouteID.isEmpty && !rightRouteID.isEmpty && leftRouteID != rightRouteID
    }

    var inputSummary: String {
        let images = messages.filter { $0.imageData != nil }.count
        let characters = messages.reduce(0) { $0 + $1.content.count }
        return "\(messages.count) 条消息 · \(characters) 字符 · \(images) 张图片"
    }

    var unavailableReason: String? {
        guard routes.count < 2 else { return nil }
        if localOnly {
            return "当前为本地优先模式，需要至少两条可用且适配输入的本地模型路线。请在 AI 设置中检查本地模型与路由选项。"
        }
        return "当前路由候选中不足两个可用且适配输入的模型。请检查供应商、模型能力及自动路由或备用模型选项。"
    }

    func start() {
        guard canStart else { return }
        let currentRoutes = ModelCompare.eligibleRoutes(settings: settings,
                                                        action: action,
                                                        messages: messages,
                                                        routingMetrics: metricsStore.snapshot())
        guard settings.redactionEnabled == redactionEnabled,
              settings.redactionRules == redactionRules,
              settings.prefersLocalModelRoutes == localOnly,
              let leftRoute = routes.first(where: { Self.routeID($0) == leftRouteID }),
              let rightRoute = routes.first(where: { Self.routeID($0) == rightRouteID }),
              currentRoutes.contains(leftRoute), currentRoutes.contains(rightRoute),
              let leftSettings = AIRequestRouter.scopedSettings(from: settings, route: leftRoute),
              let rightSettings = AIRequestRouter.scopedSettings(from: settings, route: rightRoute) else {
            preparationError = "配置已变更或所选模型不再适配，请关闭对照窗口后重新打开并确认。"
            return
        }
        let left = ModelCompareRequest(route: leftRoute, settings: leftSettings,
                                       session: session, metricsStore: metricsStore)
        let right = ModelCompareRequest(route: rightRoute, settings: rightSettings,
                                        session: session, metricsStore: metricsStore)
        self.left = left
        self.right = right
        hasStarted = true
        isRunning = true
        left.onFinished = { [weak self] in self?.requestFinished() }
        right.onFinished = { [weak self] in self?.requestFinished() }
        left.start(messages: messages, action: action)
        right.start(messages: messages, action: action)
    }

    func cancelAll() {
        left?.cancel()
        right?.cancel()
    }

    func close() {
        closed = true
        comparisonGeneration = UUID()
        cancelAll()
    }

    func choose(_ request: ModelCompareRequest) {
        guard request.canChoose else { return }
        selectedRouteID = Self.routeID(request.route)
    }

    private func requestFinished() {
        guard let left, let right else { return }
        isRunning = left.isRunning || right.isRunning || left.status == .pending || right.status == .pending
        guard !closed, !isRunning, comparison == nil, !isComparing else { return }
        guard left.status == .succeeded, right.status == .succeeded else { return }
        isComparing = true
        let generation = comparisonGeneration
        let leftSide = ModelCompare.Side(title: left.title, text: left.output)
        let rightSide = ModelCompare.Side(title: right.title, text: right.output)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let comparison = ModelCompare.compare(left: leftSide, right: rightSide)
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed, self.comparisonGeneration == generation else { return }
                self.comparison = comparison
                self.isComparing = false
            }
        }
    }
}
