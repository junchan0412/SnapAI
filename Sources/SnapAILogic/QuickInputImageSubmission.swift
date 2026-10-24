import Foundation

package enum QuickInputImageMode: String, CaseIterable, Identifiable {
    case image
    case text
    case imageAndText

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .image: return "原图"
        case .text: return "OCR 文字"
        case .imageAndText: return "图文一起"
        }
    }

    package var requiresRecognition: Bool { self != .image }
}

package struct QuickInputSubmission: Equatable {
    package var text: String
    package var imageData: Data?
    package var imageMimeType: String
}

package struct QuickInputImageInput {
    package enum Recognition: Equatable {
        case notStarted
        case recognizing
        case ready(String)
        case unavailable
        case failed(SnapAIImageTextRecognition.Failure)

        package var failureMessage: String? {
            switch self {
            case .unavailable: return "未识别到可靠文字。原图仍已保留，可重试或选择原图发送。"
            case .failed(let failure): return failure.userMessage
            default: return nil
            }
        }
    }

    package private(set) var imageData: Data?
    package private(set) var mimeType = "image/png"
    package var mode: QuickInputImageMode = .image
    package private(set) var recognition: Recognition = .notStarted
    private var generation = UUID()

    package init() {}

    package mutating func attach(data: Data, mimeType: String) {
        clear()
        imageData = data
        self.mimeType = mimeType
    }

    package mutating func clear() {
        generation = UUID()
        imageData = nil
        mimeType = "image/png"
        mode = .image
        recognition = .notStarted
    }

    package mutating func beginRecognition() -> UUID? {
        guard imageData != nil, recognition != .recognizing else { return nil }
        generation = UUID()
        recognition = .recognizing
        return generation
    }

    @discardableResult
    package mutating func completeRecognition(outcome: SnapAIImageTextRecognition.Outcome, generation: UUID) -> Bool {
        guard self.generation == generation, recognition == .recognizing, imageData != nil else { return false }
        switch outcome {
        case .recognized(let result):
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            recognition = text.isEmpty ? .unavailable : .ready(text)
        case .noReliableText: recognition = .unavailable
        case .failed(let failure): recognition = .failed(failure)
        case .cancelled: recognition = .notStarted
        }
        return true
    }

    package func submission(prompt: String) -> QuickInputSubmission? {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let imageData else {
            return prompt.isEmpty ? nil : QuickInputSubmission(text: prompt, imageData: nil, imageMimeType: "image/png")
        }
        switch mode {
        case .image:
            return QuickInputSubmission(text: prompt, imageData: imageData, imageMimeType: mimeType)
        case .text, .imageAndText:
            guard case .ready(let recognizedText) = recognition else { return nil }
            let text = prompt.isEmpty ? recognizedText : prompt + "\n\n图片中的文字：\n" + recognizedText
            return QuickInputSubmission(text: text,
                                        imageData: mode == .imageAndText ? imageData : nil,
                                        imageMimeType: mode == .imageAndText ? mimeType : "image/png")
        }
    }
}

package enum ScreenCaptureMode: String, CaseIterable, Identifiable {
    case region
    case window
    case screen

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .region: return "选择区域…"
        case .window: return "选择窗口…"
        case .screen: return "截取主屏幕"
        }
    }

    package var isInteractive: Bool { self != .screen }

    package func arguments(outputURL: URL) -> [String] {
        let options: [String]
        switch self {
        case .region: options = ["-i", "-s"]
        case .window: options = ["-i", "-w", "-o"]
        case .screen: options = ["-m"]
        }
        return ["-x", "-t", "png"] + options + [outputURL.path]
    }

    package func wasCancelled(exitStatus: Int32, outputExists: Bool) -> Bool {
        isInteractive && exitStatus == 1 && !outputExists
    }
}
