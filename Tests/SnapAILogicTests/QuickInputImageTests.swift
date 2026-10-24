import Foundation
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func testQuickInputImageSubmissionModesKeepOriginalAndSnapshot() {
    var input = QuickInputImageInput()
    let image = Data("synthetic-image-payload".utf8)
    input.attach(data: image, mimeType: "image/jpeg")
    let generation = input.beginRecognition()!
    let originalSnapshot = input.submission(prompt: "  分析图表  ")
    expect(originalSnapshot?.text == "分析图表" && originalSnapshot?.imageData == image,
           "original image can be sent while OCR runs without adding unfinished text")
    input.mode = .text
    expect(input.submission(prompt: "分析图表") == nil, "OCR-only sending waits for completed recognition")
    input.mode = .imageAndText
    expect(input.submission(prompt: "分析图表") == nil, "combined sending also waits for recognition")
    expect(input.completeRecognition(outcome: .recognized(.init(text: "  一月 20 二月 30  ", confidence: 1)), generation: generation), "current OCR result is accepted")
    expect(input.imageData == image && input.mimeType == "image/jpeg", "OCR completion preserves the original image")
    let combined = input.submission(prompt: "分析图表")
    expect(combined?.text == "分析图表\n\n图片中的文字：\n一月 20 二月 30" && combined?.imageData == image,
           "combined snapshot contains the prompt, recognized text and retained image")
    input.mode = .text
    let textOnly = input.submission(prompt: "")
    expect(textOnly?.text == "一月 20 二月 30" && textOnly?.imageData == nil,
           "text-only submission omits image bytes without deleting the attachment")
    input.clear()
    expect(originalSnapshot?.imageData == image && originalSnapshot?.text == "分析图表" && combined?.imageData == image,
           "captured submissions do not change when OCR finishes, mode changes or attachment clears")
    expect(input.submission(prompt: " \n ") == nil && input.submission(prompt: "纯文本")?.text == "纯文本",
           "attachment-free submissions retain ordinary text validation")
}

func testQuickInputImageRecognitionRejectsStaleResultsAndRecovers() {
    var input = QuickInputImageInput()
    input.attach(data: Data("first".utf8), mimeType: "image/png")
    let oldGeneration = input.beginRecognition()!
    input.attach(data: Data("second".utf8), mimeType: "image/jpeg")
    expect(!input.completeRecognition(outcome: .recognized(.init(text: "old text", confidence: 1)), generation: oldGeneration),
           "replacing an image invalidates OCR even when automatic recognition is disabled for the new image")
    expect(input.recognition == .notStarted && input.mode == .image, "new attachment starts with an explicit original-image mode")
    let generation = input.beginRecognition()!
    expect(input.beginRecognition() == nil, "duplicate recognition does not start another task")
    input.mode = .text
    _ = input.completeRecognition(outcome: .noReliableText, generation: generation)
    expect(input.recognition == .unavailable && input.submission(prompt: "问题") == nil,
           "failed OCR does not silently change a text-only request into an image request")
    input.mode = .image
    expect(input.submission(prompt: "问题")?.imageData == Data("second".utf8),
           "switching back to original image recovers sending after OCR failure")
    let retry = input.beginRecognition()!
    expect(!input.completeRecognition(outcome: .recognized(.init(text: "late result", confidence: 1)), generation: generation), "retry rejects an earlier task result")
    _ = input.completeRecognition(outcome: .recognized(.init(text: "retry text", confidence: 1)), generation: retry)
    input.mode = .text
    expect(input.submission(prompt: "")?.text == "retry text", "explicit OCR retry can recover text-only submission")
    let clearedGeneration = input.beginRecognition()!
    input.clear()
    expect(!input.completeRecognition(outcome: .recognized(.init(text: "removed image", confidence: 1)), generation: clearedGeneration),
           "removing an attachment prevents a late OCR callback from restoring its text")
}

func testScreenCaptureModesUseBoundedSystemSelection() {
    let url = URL(fileURLWithPath: "/tmp/snapai-fixture path.png")
    expect(ScreenCaptureMode.region.arguments(outputURL: url) == ["-x", "-t", "png", "-i", "-s", url.path],
           "region capture uses the system's mouse-selection mode and passes the path as one argument")
    expect(ScreenCaptureMode.window.arguments(outputURL: url) == ["-x", "-t", "png", "-i", "-w", "-o", url.path],
           "window capture selects one window without its shadow")
    expect(ScreenCaptureMode.screen.arguments(outputURL: url) == ["-x", "-t", "png", "-m", url.path],
           "full-screen capture produces one main-display file without extra monitor images")
    expect(ScreenCaptureMode.region.wasCancelled(exitStatus: 1, outputExists: false), "interactive escape is a cancellation")
    expect(!ScreenCaptureMode.screen.wasCancelled(exitStatus: 1, outputExists: false), "full-screen command failures are not hidden as cancellations")
    expect(!ScreenCaptureMode.window.wasCancelled(exitStatus: 15, outputExists: false), "terminated capture commands still report a failure")
}

func testQuickInputImageRecognitionKeepsFailureReasonsAndOriginal() {
    let image = Data("retained-image".utf8)
    for failure in [SnapAIImageTextRecognition.Failure.timedOut, .system(domain: "VisionFixture", code: 7), .invalidImage] {
        var input = QuickInputImageInput()
        input.attach(data: image, mimeType: "image/png")
        let generation = input.beginRecognition()!
        input.mode = .imageAndText
        expect(input.completeRecognition(outcome: .failed(failure), generation: generation), "current OCR failure is accepted")
        expect(input.recognition == .failed(failure) && input.recognition.failureMessage == failure.userMessage,
               "OCR failure reason survives the UI state transition")
        expect(input.imageData == image && input.submission(prompt: "问题") == nil,
               "OCR failures preserve the image and do not silently submit a different mode")
        input.mode = .image
        expect(input.submission(prompt: "问题")?.imageData == image, "original-image sending remains available after OCR failure")
        let retry = input.beginRecognition()!
        expect(!input.completeRecognition(outcome: .failed(failure), generation: generation), "late failures cannot overwrite a retry")
        _ = input.completeRecognition(outcome: .recognized(.init(text: "Recovered text", confidence: 1)), generation: retry)
        input.mode = .text
        expect(input.submission(prompt: "")?.text == "Recovered text", "retry recovers from timeout and system failure")
    }
    expect(QuickInputImageInput.Recognition.unavailable.failureMessage != SnapAIImageTextRecognition.Failure.timedOut.userMessage,
           "no reliable text and timeout have distinct user-facing explanations")
    var cancelled = QuickInputImageInput()
    cancelled.attach(data: image, mimeType: "image/png")
    cancelled.mode = .imageAndText
    let generation = cancelled.beginRecognition()!
    expect(cancelled.completeRecognition(outcome: .cancelled, generation: generation),
           "current recognition accepts cancellation")
    expect(cancelled.recognition == .notStarted && cancelled.imageData == image && cancelled.mode == .imageAndText,
           "cancellation resets recognition while preserving the original image and selected mode")
    expect(cancelled.beginRecognition() != nil, "cancelled recognition can retry")
}
