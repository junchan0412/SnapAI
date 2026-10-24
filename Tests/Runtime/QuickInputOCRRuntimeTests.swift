import AppKit
import Combine
@testable import SnapAILogic
import os

@MainActor
func runQuickInputOCRRuntimeTests() async -> [String] {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append("Quick input OCR: " + message) }
    }
    func waitUntil(_ message: String, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        check(condition(), message)
    }

    let suite = "com.snapai.quick-input-ocr-runtime.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings()
    settings.persistenceDefaults = defaults
    settings.iCloudSyncEnabled = false
    settings.imageOCREnabled = true
    defer { defaults.removePersistentDomain(forName: suite) }

    guard let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return ["Quick input OCR: cannot create image fixture"]
    }
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    guard let image = context.makeImage(),
          let payload = NSImage(cgImage: image, size: NSSize(width: 100, height: 100)).snapAIOptimizedData() else {
        return ["Quick input OCR: cannot encode image fixture"]
    }

    for operation in ["remove", "replace", "crop", "release", "hide"] {
        let state = OSAllocatedUnfairLock(initialState: (calls: 0, cancelled: false, finished: false, release: false))
        var model: QuickInputModel? = QuickInputModel(settings: settings, recognizeText: { _ in
            let call = state.withLock { $0.calls += 1; return $0.calls }
            if call > 1 { return .recognized(.init(text: "Current image recognized text", confidence: 1)) }
            let deadline = Date().addingTimeInterval(5)
            while !Task.isCancelled, !state.withLock({ $0.release }), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.005)
            }
            state.withLock { $0.cancelled = Task.isCancelled; $0.finished = true }
            return .recognized(.init(text: "Previous image recognized text", confidence: 1))
        })
        weak var weakModel = model
        var publishedText: [String] = []
        let observation = model!.$imageInput.sink { input in
            if case .ready(let text) = input.recognition { publishedText.append(text) }
        }
        model!.text = "保留提问草稿"
        model!.attachImage(payload)
        model!.selectImageMode(.imageAndText)
        await waitUntil("\(operation) starts the first OCR closure") { state.withLock { $0.calls == 1 } }

        switch operation {
        case "remove": model!.clearImage()
        case "replace": model!.attachImage(payload)
        case "crop":
            check(model!.cropImage(image, selection: CGRect(x: 10, y: 10, width: 50, height: 50),
                                   displaySize: CGSize(width: 100, height: 100)), "crop succeeds")
            check(model!.imageInput.mode == .imageAndText, "crop preserves the selected submission mode")
        case "release": model = nil
        default:
            let controller = QuickInputController(model: model!)
            controller.hide()
            check(model!.text == "保留提问草稿" && model!.imageData == payload.data &&
                  model!.imageInput.mode == .imageAndText && model!.imageInput.recognition == .recognizing,
                  "hide preserves text, original image, mode and running OCR")
            state.withLock { $0.release = true }
        }

        await waitUntil("\(operation) lets the first OCR closure finish") { state.withLock { $0.finished } }
        if operation == "hide" {
            check(!state.withLock { $0.cancelled }, "hide does not cancel OCR")
            await waitUntil("hidden draft receives its successful OCR result") {
                model?.imageInput.recognition == .ready("Previous image recognized text")
            }
            check(model!.imageData == payload.data && model!.imageInput.mode == .imageAndText,
                  "successful OCR keeps original image and mode")
        } else {
            check(state.withLock { $0.cancelled }, "\(operation) cancels the running OCR task")
            if operation == "release" {
                check(weakModel == nil, "running OCR does not retain the model")
            } else if operation == "remove" {
                check(model!.imageData == nil && model!.imageInput.recognition == .notStarted,
                      "remove clears the attachment and resets recognition")
            } else {
                await waitUntil("\(operation) publishes only the new image result") {
                    model?.imageInput.recognition == .ready("Current image recognized text")
                }
                check(model!.imageData != nil, "\(operation) keeps the current image")
            }
            check(!publishedText.contains("Previous image recognized text"), "\(operation) never publishes the cancelled result")
        }
        observation.cancel()
        model?.clearImage()
    }
    return failures
}
