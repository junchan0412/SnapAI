import Foundation
import Vision

/// 截图/粘贴图片的本地 OCR:Vision VNRecognizeTextRequest 抽取文字。
///
/// 设计约束:
/// 1. 纯逻辑层(AppKit 仅用于 CGImage 桥接,不依赖 SwiftUI),可进逻辑测试。
/// 2. 同步 API + 内部信号量,调用方(QuickInputModel)在后台队列调用,避免阻塞主线程。
/// 3. 失败静默返回 nil —— OCR 只是"省流量/省隐私"的优化路径,绝不能阻塞发送。
package enum SnapAIImageTextRecognition {
    package struct Result: Equatable {
        package var text: String
        /// 识别到的平均置信度(0...1),调用方可按阈值决定是否采用。
        package var confidence: Double
    }

    /// 最小采用阈值:低于此置信度视为"图里没可靠文字",继续走视觉模型。
    package static let minimumConfidence = 0.5
    /// 最小文本长度:过短的识别结果大概率是图标/水印噪声。
    package static let minimumTextLength = 8

    /// 从图片数据识别文字。返回 nil 表示无可靠文本(继续走视觉模型)。
    package static func recognizeText(in imageData: Data,
                                      timeout: TimeInterval = 8) -> Result? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return recognizeText(in: cgImage, timeout: timeout)
    }

    package static func recognizeText(in cgImage: CGImage,
                                      timeout: TimeInterval = 8) -> Result? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // 中英文都常见:明确指定避免系统按首选语言裁剪候选。
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let semaphore = DispatchSemaphore(value: 0)
        var requestError: Error?
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                requestError = error
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success,
              requestError == nil else {
            return nil
        }
        guard let observations = request.results as? [VNRecognizedTextObservation],
              !observations.isEmpty else {
            return nil
        }
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
        guard text.count >= minimumTextLength else { return nil }
        let average = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        guard average >= minimumConfidence else { return nil }
        return Result(text: text, confidence: average)
    }
}
