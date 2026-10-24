import Combine
import Foundation
import SnapAILogic

enum SnapAIIntentError: LocalizedError, CustomNSError {
    case emptyInput(String)
    case appUnavailable(String)
    case actionUnavailable
    case privacyCancelled
    case cancelled
    case timedOut
    case requestFailed(String)
    case emptyResponse

    var code: String {
        switch self {
        case .emptyInput: return "empty_input"
        case .appUnavailable: return "app_unavailable"
        case .actionUnavailable: return "action_unavailable"
        case .privacyCancelled: return "privacy_cancelled"
        case .cancelled: return "cancelled"
        case .timedOut: return "timed_out"
        case .requestFailed: return "request_failed"
        case .emptyResponse: return "empty_response"
        }
    }

    var message: String {
        switch self {
        case .emptyInput(let message), .appUnavailable(let message): return message
        case .actionUnavailable: return "未找到启用的动作，请检查动作名称或设置。"
        case .privacyCancelled: return "已取消发送前的隐私确认，未向 AI 发送内容。"
        case .cancelled: return "已取消 SnapAI 处理。"
        case .timedOut: return "SnapAI 处理超时，请重试或增加等待时间。"
        case .requestFailed(let message): return SensitiveTextSanitizer.sanitizedMessage(message)
        case .emptyResponse: return "AI 未返回正文，请重试。"
        }
    }

    var errorDescription: String? { "[\(code)] \(message)" }
    static var errorDomain: String { "com.snapai.automation" }
    var errorCode: Int {
        switch self {
        case .emptyInput: return 1
        case .appUnavailable: return 2
        case .actionUnavailable: return 3
        case .privacyCancelled: return 4
        case .cancelled: return 5
        case .timedOut: return 6
        case .requestFailed: return 7
        case .emptyResponse: return 8
        }
    }
    var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: errorDescription ?? message, "code": code]
    }

    static func normalized(_ error: Error) -> SnapAIIntentError {
        if let error = error as? SnapAIIntentError { return error }
        if error is CancellationError { return .cancelled }
        return .requestFailed(error.localizedDescription)
    }
}

struct AutomationActionResult: Codable {
    struct Failure: Codable {
        var code: String
        var message: String
    }

    var status: String
    var text: String
    var error: Failure?

    init(text: String) {
        status = "succeeded"
        self.text = text
    }

    init(error: Error) {
        let failure = SnapAIIntentError.normalized(error)
        status = "failed"
        text = ""
        self.error = Failure(code: failure.code, message: failure.message)
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

@MainActor
final class AutomationActionExecution {
    private let viewModel: ResultViewModel
    private var completion: CheckedContinuation<String, Error>?
    private var observation: AnyCancellable?
    private var timeoutTask: Task<Void, Never>?

    init(settings: AppSettings, session: URLSession = .shared) {
        viewModel = ResultViewModel(settings: settings, session: session)
    }

    func run(text: String,
             action: AIAction,
             timeout: TimeInterval = 120,
             prepareSubmission: (String, AIAction) -> PrivacyPreparedSubmission?) async throws -> String {
        try Task.checkCancellation()
        guard let prepared = prepareSubmission(text, action) else {
            try Task.checkCancellation()
            throw SnapAIIntentError.privacyCancelled
        }
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                guard !Task.isCancelled else {
                    finish(.failure(SnapAIIntentError.cancelled))
                    return
                }
                observation = viewModel.$isGenerating.dropFirst().sink { [weak self] generating in
                    guard !generating else { return }
                    // Published 通知发生在赋值前，下一次 actor 调度再读取最终正文与错误。
                    Task { @MainActor [weak self] in self?.completeIfReady() }
                }
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeout)) }
                    catch { return }
                    self?.finish(.failure(SnapAIIntentError.timedOut))
                }
                viewModel.start(text: prepared.text,
                                action: action,
                                submissionPrivacy: prepared.diagnostic,
                                autoReplaceEnabled: false,
                                preparedMessages: prepared.messages)
                completeIfReady()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(SnapAIIntentError.cancelled))
            }
        }
    }

    private func completeIfReady() {
        guard completion != nil, !viewModel.isGenerating else { return }
        if let message = viewModel.errorMessage {
            finish(.failure(SnapAIIntentError.requestFailed(message)))
        } else if viewModel.incompleteResultReason != nil {
            finish(.failure(SnapAIIntentError.cancelled))
        } else if viewModel.completeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finish(.failure(SnapAIIntentError.emptyResponse))
        } else {
            finish(.success(viewModel.completeText))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation = completion else { return }
        completion = nil
        observation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        switch result {
        case .success: viewModel.revealFullOutput()
        case .failure: viewModel.cancel()
        }
        continuation.resume(with: result)
    }
}
