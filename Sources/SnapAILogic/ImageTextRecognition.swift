import Foundation
import Vision
import os

/// 截图/粘贴图片的本地 OCR:Vision VNRecognizeTextRequest 抽取文字。
///
/// 设计约束:
/// 1. 纯逻辑层(AppKit 仅用于 CGImage 桥接,不依赖 SwiftUI),可进逻辑测试。
/// 2. 同步 API + 内部信号量,调用方(QuickInputModel)在可取消的后台 Task 调用。
/// 3. 失败保留原因,调用方可重试或继续发送原图。
package enum SnapAIImageTextRecognition {
    package struct Result: Equatable, Sendable {
        package var text: String
        /// 识别到的平均置信度(0...1),调用方可按阈值决定是否采用。
        package var confidence: Double
    }

    package enum Outcome: Equatable, Sendable {
        case recognized(Result)
        case noReliableText
        case failed(Failure)
        case cancelled
    }

    package enum Failure: Equatable, Sendable {
        case invalidImage
        case timedOut
        case system(domain: String, code: Int)

        package var userMessage: String {
            switch self {
            case .invalidImage: return "无法读取用于识别的图片。原图仍已保留，可重试或选择原图发送。"
            case .timedOut: return "本机文字识别超时。原图仍已保留，可重试或选择原图发送。"
            case .system: return "系统文字识别暂时失败。原图仍已保留，可重试或选择原图发送。"
            }
        }
    }

    /// 最小采用阈值:低于此置信度视为"图里没可靠文字"。
    package static let minimumConfidence = 0.5
    /// 最小文本长度:过短的识别结果大概率是图标/水印噪声。
    package static let minimumTextLength = 8
    package static let defaultTimeout: TimeInterval = 45

    /// 从图片数据识别文字,区分无可靠文本与解码、系统或超时失败。
    package static func recognizeText(in imageData: Data,
                                      timeout: TimeInterval = defaultTimeout) -> Outcome {
        guard !Task.isCancelled else { return .cancelled }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .failed(.invalidImage)
        }
        return recognizeText(in: cgImage, timeout: timeout)
    }

    package static func recognizeText(in cgImage: CGImage,
                                      timeout: TimeInterval = defaultTimeout) -> Outcome {
        guard !Task.isCancelled else { return .cancelled }
        guard timeout > 0 else { return .failed(.timedOut) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // 中英文都常见:明确指定避免系统按首选语言裁剪候选。
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        return recognizeText(using: request, timeout: timeout) {
            do {
                try handler.perform([request])
            } catch {
                let failure = error as NSError
                guard failure.domain == "TextRecognition.CRImageReaderError", failure.code == 9 else { throw error }
                let stages = try request.supportedComputeStageDevices
                var configuredCPU = false
                for (stage, devices) in stages {
                    if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                        request.setComputeDevice(cpu, for: stage)
                        configuredCPU = true
                    }
                }
                guard configuredCPU else { throw error }
                try handler.perform([request])
            }
        }
    }

    static func recognizeText(using request: VNRecognizeTextRequest,
                              timeout: TimeInterval,
                              queue: DispatchQueue = .global(qos: .userInitiated),
                              perform: @escaping @Sendable () throws -> Void) -> Outcome {
        guard !Task.isCancelled else {
            request.cancel()
            return .cancelled
        }
        guard timeout > 0 else { return .failed(.timedOut) }
        let semaphore = DispatchSemaphore(value: 0)
        let completion = OSAllocatedUnfairLock(initialState: (outcome: Outcome?.none, perform: Optional(perform)))
        queue.async {
            defer { semaphore.signal() }
            guard let perform = completion.withLock({ state in
                defer { state.perform = nil }
                return state.perform
            }) else { return }
            let outcome: Outcome
            do {
                try perform()
                outcome = recognizedOutcome(from: request.results ?? [])
            } catch {
                let error = error as NSError
                outcome = .failed(.system(domain: error.domain, code: error.code))
            }
            completion.withLock { if $0.outcome == nil { $0.outcome = outcome } }
        }
        let deadline = DispatchTime.now() + timeout
        while true {
            if Task.isCancelled {
                completion.withLock { $0 = (.cancelled, nil) }
                request.cancel()
                return .cancelled
            }
            if let outcome = completion.withLock({ $0.outcome }) { return outcome }
            guard DispatchTime.now() < deadline else {
                completion.withLock { $0 = (.failed(.timedOut), nil) }
                request.cancel()
                return .failed(.timedOut)
            }
            _ = semaphore.wait(timeout: min(deadline, .now() + 0.05))
        }
    }

    private static func recognizedOutcome(from observations: [VNRecognizedTextObservation]) -> Outcome {
        var lines: [String] = []
        var confidences: [Double] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            lines.append(line)
            confidences.append(Double(candidate.confidence))
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minimumTextLength else { return .noReliableText }
        let average = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        guard average >= minimumConfidence else { return .noReliableText }
        return .recognized(Result(text: text, confidence: average))
    }
}
