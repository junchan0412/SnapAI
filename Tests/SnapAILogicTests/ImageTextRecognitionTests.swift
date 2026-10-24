import AppKit
import Vision
import os
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func testImageTextRecognitionDetectsEnglishAndChinese() {
    let fixtures = [
        ["SnapAI OCR and crop fixture", "Blue: 20   Orange: 32", "Keep the original chart image."],
        ["本地识别与裁剪测试", "蓝色：20 橙色：32", "请保留原始图表图片。"]
    ]
    for lines in fixtures {
        let image = imageTextRecognitionFixture(lines: lines)
        let outcome = SnapAIImageTextRecognition.recognizeText(in: image)
        guard case .recognized(let result) = outcome else {
            expect(false, "clear English and Chinese images produce reliable OCR without changing confidence thresholds: \(outcome)")
            continue
        }
        expect(result.text.contains(lines[2]), "OCR preserves the full sentence in the detected language")
        expect(result.confidence >= SnapAIImageTextRecognition.minimumConfidence,
               "recognized text satisfies the existing confidence threshold")
    }
}

func testImageTextRecognitionDistinguishesNoTextAndTimeout() {
    let blank = imageTextRecognitionFixture(lines: [])
    let outcome = SnapAIImageTextRecognition.recognizeText(in: blank)
    expect(outcome == .noReliableText,
           "a valid blank image is distinct from a failed recognition request: \(outcome)")
    expect(SnapAIImageTextRecognition.recognizeText(in: blank, timeout: 0) == .failed(.timedOut),
           "an exhausted time budget reports timeout instead of claiming the image has no text")
}

func testImageTextRecognitionCancelsRunningAndPrestartRequests() {
    expect(SnapAIImageTextRecognition.defaultTimeout == 45, "cancellation keeps the 45-second cold-start budget")
    for queued in [false, true] {
        let request = CancellableTextRecognitionRequest()
        let queue = DispatchQueue(label: "snapai.ocr-cancellation-test")
        let queueGate = DispatchSemaphore(value: 0)
        let entered = DispatchSemaphore(value: 0)
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let result = OSAllocatedUnfairLock<SnapAIImageTextRecognition.Outcome?>(initialState: nil)
        if queued { queue.async { queueGate.wait() } }
        let task = Task.detached {
            entered.signal()
            let outcome = SnapAIImageTextRecognition.recognizeText(using: request, timeout: 45, queue: queue) {
                calls.withLock { $0 += 1 }
                started.signal()
                _ = request.cancellation.wait(timeout: .now() + 2)
            }
            result.withLock { $0 = outcome }
            finished.signal()
        }
        expect(entered.wait(timeout: .now() + 2) == .success, "recognition task starts")
        if !queued {
            expect(started.wait(timeout: .now() + 2) == .success, "running fixture reaches request execution")
        }
        let cancelledAt = Date()
        task.cancel()
        expect(finished.wait(timeout: .now() + 1) == .success, "cancelled recognition exits without waiting for the cold-start timeout")
        expect(result.withLock { $0 } == .cancelled, "cancellation is distinct from no reliable text, system failure and timeout")
        expect(request.cancelCount.withLock { $0 } == 1, "task cancellation calls VNRequest.cancel exactly once")
        expect(Date().timeIntervalSince(cancelledAt) < 1, "cancellation promptly releases the waiting task")
        queueGate.signal()
        queue.sync {}
        expect(calls.withLock { $0 } == (queued ? 0 : 1), "recognition cancelled before queue execution never starts the model")
    }

    let ready = DispatchSemaphore(value: 0)
    let gate = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let result = OSAllocatedUnfairLock<SnapAIImageTextRecognition.Outcome?>(initialState: nil)
    let task = Task.detached {
        ready.signal()
        gate.wait()
        result.withLock { $0 = SnapAIImageTextRecognition.recognizeText(in: Data()) }
        finished.signal()
    }
    expect(ready.wait(timeout: .now() + 2) == .success, "pre-cancelled fixture is ready")
    task.cancel()
    gate.signal()
    expect(finished.wait(timeout: .now() + 1) == .success && result.withLock { $0 } == .cancelled,
           "an already cancelled task returns before decoding invalid image data")
}

private final class CancellableTextRecognitionRequest: VNRecognizeTextRequest, @unchecked Sendable {
    let cancellation = DispatchSemaphore(value: 0)
    let cancelCount = OSAllocatedUnfairLock(initialState: 0)

    override func cancel() {
        cancelCount.withLock { $0 += 1 }
        cancellation.signal()
        super.cancel()
    }
}

private func imageTextRecognitionFixture(lines: [String]) -> CGImage {
    let context = CGContext(data: nil, width: 1800, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: 2, y: 2)
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    if !lines.isEmpty {
        NSColor.systemBlue.setFill()
        NSRect(x: 80, y: 100, width: 180, height: 200).fill()
        NSColor.systemOrange.setFill()
        NSRect(x: 320, y: 100, width: 180, height: 320).fill()
        (lines.joined(separator: "\n") as NSString).draw(in: NSRect(x: 50, y: 450, width: 820, height: 120),
                                                         withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    let resized = CGContext(data: nil, width: 1600, height: 1066, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    resized.interpolationQuality = .high
    resized.draw(context.makeImage()!, in: CGRect(x: 0, y: 0, width: 1600, height: 1066))
    return resized.makeImage()!
}
