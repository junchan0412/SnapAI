import AppKit
import Foundation
import SnapAILogic

private final class EscapeRecorder: NSView {
    private(set) var escapeCount = 0
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { escapeCount += 1 } else { super.keyDown(with: event) }
    }
}

@MainActor
private final class AppRuntimeSmokeDelegate: NSObject, NSApplicationDelegate {
    private var failures: [String] = []
    private var suites: [String] = []
    private let fixtureRoot: URL
    private let resultURL: URL

    init(fixtureRoot: URL, resultURL: URL) {
        self.fixtureRoot = fixtureRoot
        self.resultURL = resultURL
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Task { @MainActor in
            await testReplacingActiveRequest()
            await testReplacingDrainingRequest()
            await testCancellationAndErrors()
            await testUnavailableReplacement()
            await testHistorySaveFailureAndDisabledHistory()
            await testQuickInputSubmissionAcceptance()
            await testPanelPresentationRace()
            await testSavedPanelSizes()
            await testReusableSettingsWindow()
            await testEscapeOwnership()
            await finish()
        }
    }

    private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures.append(message) }
    }

    private func waitUntil(_ message: String, condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(4)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        check(condition(), message)
    }

    private func settings(_ name: String, historyFails: Bool = false) -> AppSettings {
        let suite = "com.snapai.runtime-tests.\(UUID().uuidString)"
        suites.append(suite)
        let settings = AppSettings()
        settings.persistenceDefaults = UserDefaults(suiteName: suite)!
        var databaseURL = fixtureRoot.appendingPathComponent("\(name).sqlite")
        if historyFails {
            let blocker = fixtureRoot.appendingPathComponent("\(name)-blocker")
            try! Data("fixture".utf8).write(to: blocker)
            databaseURL = blocker.appendingPathComponent("history.sqlite")
        }
        settings.persistenceHistoryStore = HistoryStore(url: databaseURL)
        let provider = AIProvider(id: "fixture-\(name)", name: "Offline fixture",
                                  baseURL: "https://snapai-app.test/v1", apiKey: "fixture-key",
                                  models: [AIModelEntry(name: "fixture-model")])
        settings.providers = [provider]
        settings.activeProviderID = provider.id
        settings.activeModel = "fixture-model"
        settings.secretStoreCache = [provider.id: provider.apiKey]
        settings.typewriterSpeed = .off
        settings.autoRouteEnabled = false
        settings.fallbackEnabled = false
        settings.iCloudSyncEnabled = false
        settings.onboardingDone = true
        settings.resultPanelDismissMode = .alwaysKeep
        settings.actions = [action()]
        return settings
    }

    private func action(thinking: Bool = false) -> AIAction {
        AIAction(name: "Runtime fixture", prompt: "{{text}}", replaceByDefault: true,
                 thinkingMode: thinking, saveHistory: true)
    }

    private func content(_ text: String, done: Bool = true) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": text]]]])
        return "data: \(String(decoding: data, as: UTF8.self))\n\n" + (done ? "data: [DONE]\n\n" : "")
    }

    private func testReplacingActiveRequest() async {
        let settings = settings("replace-active")
        let vm = ResultViewModel(settings: settings)
        var replacements: [String] = []
        vm.onReplace = { _, replacement in replacements.append(replacement) }
        StreamFixtureProtocol.store.resetPlans([
            StreamFixturePlan(chunks: [(0, content("old prefix", done: false)),
                                      (0.25, "event: error\ndata: {\"message\":\"old error\"}\n\n")]),
            StreamFixturePlan(chunks: [(0, content("new result"))])
        ])
        vm.start(text: "old source", action: action(), autoReplaceEnabled: true)
        await waitUntil("the old request begins receiving output") { vm.completeText == "old prefix" }
        vm.start(text: "new source", action: action(), autoReplaceEnabled: true)
        await waitUntil("the replacement VM request completes") { !vm.isStreaming && vm.completeText == "new result" }
        try? await Task.sleep(nanoseconds: 300_000_000)
        check(vm.output == "new result" && vm.errorMessage == nil && vm.thinkingText.isEmpty,
              "an old client cannot change the new VM output, thinking or error")
        check(settings.history.map(\.output) == ["new result"] && replacements == ["new result"],
              "only the replacement request saves history and writes back")
        check(settings.actionUsageCounts[action().name] == 1, "superseded requests do not record success usage")
    }

    private func testReplacingDrainingRequest() async {
        let settings = settings("replace-drain")
        settings.typewriterSpeed = .slow
        let vm = ResultViewModel(settings: settings)
        var replacements: [String] = []
        vm.onReplace = { _, replacement in replacements.append(replacement) }
        let old = String(repeating: "old ", count: 200)
        StreamFixtureProtocol.store.reset([(200, content(old)), (200, content("新"))])
        vm.start(text: "old source", action: action(), autoReplaceEnabled: true)
        await waitUntil("the old response enters the typewriter drain") {
            vm.completeText == old && vm.requestDiagnostics?.attempts.last?.status == .succeeded
        }
        check(vm.isStreaming && settings.history.isEmpty, "history waits for presentation completion")
        vm.start(text: "new source", action: action(), autoReplaceEnabled: true)
        await waitUntil("a new response replaces the previous drain") { !vm.isStreaming && vm.output == "新" }
        try? await Task.sleep(nanoseconds: 100_000_000)
        check(settings.history.map(\.output) == ["新"] && replacements == ["新"],
              "an old drain cannot complete, save or write back after a new request begins")
    }

    private func testCancellationAndErrors() async {
        for speed in [TypewriterSpeed.off, .slow] {
            let settings = settings("cancel-\(speed.rawValue)")
            settings.typewriterSpeed = speed
            let vm = ResultViewModel(settings: settings)
            var replacements = 0
            vm.onReplace = { _, _ in replacements += 1 }
            StreamFixtureProtocol.store.resetPlans([StreamFixturePlan(chunks: [
                (0, content("partial", done: false)), (0.2, "data: [DONE]\n\n")
            ])])
            vm.start(text: "source", action: action(), autoReplaceEnabled: true)
            await waitUntil("cancellation fixture receives partial output") { vm.completeText == "partial" }
            vm.cancel()
            try? await Task.sleep(nanoseconds: 250_000_000)
            check(!vm.isStreaming && vm.output == "partial" && vm.incompleteResultReason != nil,
                  "cancel preserves partial output in both immediate and typewriter modes")
            check(settings.history.map(\.output) == ["partial"] &&
                  settings.history.first?.displayTags.contains("部分结果") == true &&
                  settings.actionUsageCounts.isEmpty && replacements == 0,
                  "cancel saves its partial output tagged as partial, without success usage or auto-replace")

            // 取消已保存一条“部分结果”历史；后续错误循环只断言不再新增。
            let historyCountAfterCancel = settings.history.count
            for (body, thinking) in [(content("partial", done: false), false),
                                     ("data: {broken}\n\n", false),
                                     (content("<think>analysis only</think>"), true)] {
                StreamFixtureProtocol.store.reset([(200, body)])
                vm.start(text: "source", action: action(thinking: thinking), autoReplaceEnabled: true)
                await waitUntil("error or thinking-only output ends the request") { !vm.isStreaming && vm.errorMessage != nil }
                try? await Task.sleep(nanoseconds: 50_000_000)
                check(settings.history.count == historyCountAfterCancel && settings.actionUsageCounts.isEmpty && replacements == 0,
                      "errors and thinking-only responses cannot save, count success or auto-replace")
            }
        }
    }

    private func testUnavailableReplacement() async {
        let settings = settings("unavailable")
        let vm = ResultViewModel(settings: settings)
        StreamFixtureProtocol.store.resetPlans([StreamFixturePlan(chunks: [
            (0, content("old", done: false)), (0.2, "data: [DONE]\n\n")
        ])])
        vm.start(text: "old source", action: action())
        await waitUntil("the unavailable-route fixture is streaming") { vm.completeText == "old" }
        settings.providers = []
        vm.start(text: "new source", action: action())
        check(!vm.isStreaming && vm.errorMessage != nil && vm.completeText.isEmpty,
              "an unavailable replacement exits streaming instead of leaving a stuck request")
        vm.cancel()
    }

    private func testHistorySaveFailureAndDisabledHistory() async {
        let broken = settings("history-failure", historyFails: true)
        let failedVM = ResultViewModel(settings: broken)
        StreamFixtureProtocol.store.reset([(200, content("retained result"))])
        failedVM.start(text: "source", action: action())
        await waitUntil("a successful response reports its failed history write") { !failedVM.isStreaming && failedVM.completeText == "retained result" }
        check(broken.history.isEmpty && failedVM.output == "retained result" && failedVM.errorMessage == nil,
              "history write failure preserves the successful result without fabricating a history entry")
        check(failedVM.operationCoordinator.feedback?.kind == .error &&
              failedVM.operationCoordinator.feedback?.message.contains("历史保存失败") == true,
              "history write failure produces persistent actionable feedback")

        let disabled = settings("history-disabled")
        disabled.historyLimit = 0
        let disabledVM = ResultViewModel(settings: disabled)
        StreamFixtureProtocol.store.reset([(200, content("unsaved by preference"))])
        disabledVM.start(text: "source", action: action())
        await waitUntil("zero history retention completes normally") { !disabledVM.isStreaming && !disabledVM.completeText.isEmpty }
        check(disabled.history.isEmpty && disabledVM.operationCoordinator.feedback == nil,
              "intentionally disabled history is not reported as a write failure")
        let persisted = disabled.persistenceDefaults.data(forKey: AppSettings.storeKey)
            .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        check(persisted?.actionUsageCounts[action().name] == 1, "usage still persists when history is disabled")
    }

    private func testPanelPresentationRace() async {
        let panel = FloatingPanel(contentRect: NSRect(x: 120, y: 120, width: 500, height: 500))
        defer { panel.orderOut(nil) }
        FloatingPanelPresentation.present(panel, animated: false)
        var staleCompletions = 0
        FloatingPanelPresentation.dismiss(panel) { staleCompletions += 1 }
        FloatingPanelPresentation.present(panel, animated: false)
        try? await Task.sleep(nanoseconds: 350_000_000)
        check(panel.isVisible && panel.alphaValue > 0.99, "a stale dismissal cannot hide or fade a newly presented panel")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(staleCompletions == 0, "superseded animated dismissal does not call its completion")
        }
    }

    private func testQuickInputSubmissionAcceptance() async {
        let model = QuickInputModel(settings: settings("quick-submission"))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 8, bitsPerPixel: 32)!
        let color = NSColor(deviceRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(color, atX: x, y: y) } }
        let image = bitmap.representation(using: .png, properties: [:])!
        model.attachImage(SnapAIImagePayload(data: image, mimeType: "image/png"))
        model.text = "  retained draft  "
        model.submit()
        check(model.text == "  retained draft  " && model.imageData == image && !model.didJustSend,
              "missing submission handlers preserve the text and image draft")
        model.onSubmit = { _, _, _, _ in false }
        model.submit()
        check(model.text == "  retained draft  " && model.imageData == image && model.imagePreview != nil &&
              !model.didJustSend && model.transientStatus != nil,
              "privacy rejection preserves the complete draft without a sent confirmation")
        var accepted: [String] = []
        model.onSubmit = { text, _, submittedImage, _ in
            accepted.append(text)
            if accepted.count == 1 { self.check(submittedImage == image, "the accepted request receives the retained image") }
            return true
        }
        model.submit()
        check(accepted == ["retained draft"] && model.text.isEmpty && model.imageData == nil &&
              model.imagePreview == nil && model.didJustSend,
              "only accepted submissions clear the draft and show sent confirmation")
        model.submit()
        check(accepted.count == 1, "a duplicate submit event does not resend an accepted draft")
        await waitUntil("sent feedback finishes") { !model.didJustSend }
        model.text = "next draft"
        model.submit()
        check(accepted == ["retained draft", "next draft"], "a later draft can be submitted normally")
    }

    private func testSavedPanelSizes() async {
        for (name, width, height) in [("legacy-size", 420.0, 360.0), ("custom-size", 720.0, 620.0)] {
            let settings = settings(name)
            settings.panelWidth = width
            settings.panelHeight = height
            let controller = FloatingPanelController(vm: ResultViewModel(settings: settings))
            let existing = Set(NSApp.windows.map(\.windowNumber))
            controller.show()
            guard let window = NSApp.windows.first(where: { !existing.contains($0.windowNumber) && $0 is FloatingPanel }) else {
                failures.append("saved panel dimensions create a visible result window")
                continue
            }
            let visible = window.contentView?.bounds.size ?? .zero
            check(visible.width >= max(480, width) && visible.height >= max(480, height),
                  "legacy dimensions fit the new controls while larger saved dimensions are preserved")
            check(settings.panelWidth == width && settings.panelHeight == height,
                  "opening a result window does not rewrite saved custom dimensions")
            controller.hide()
            await waitUntil("the size-test window closes") { !window.isVisible }
        }
    }

    private func testReusableSettingsWindow() async {
        let settings = settings("settings-window")
        let coordinator = WindowCoordinator(settings: settings, onSettingsChange: {})
        coordinator.openSettings()
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "SnapAI.SettingsWindow" }) else {
            failures.append("the real WindowCoordinator creates its settings window")
            return
        }
        window.close()
        coordinator.openSettings()
        try? await Task.sleep(nanoseconds: 60_000_000)
        check(window.isVisible && window.contentViewController != nil,
              "deferred close cleanup cannot erase a settings window reopened immediately")
        window.close()
        await waitUntil("closed settings windows release their hosting controller") { window.contentViewController == nil }
        coordinator.openSettings()
        check(window.isVisible && window.contentViewController != nil,
              "a released settings hosting tree can be recreated in the same window")
        window.close()
        try? await Task.sleep(nanoseconds: 40_000_000)
    }

    private func testEscapeOwnership() async {
        let settings = settings("escape")
        let vm = ResultViewModel(settings: settings)
        vm.isPinned = true
        let result = FloatingPanelController(vm: vm)
        let previous = Set(NSApp.windows.map(\.windowNumber))
        result.show()
        guard let resultWindow = NSApp.windows.first(where: { !previous.contains($0.windowNumber) && $0 is FloatingPanel }) else {
            failures.append("the real result controller creates its panel")
            return
        }
        let recorder = EscapeRecorder(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        let other = NSWindow(contentRect: recorder.frame, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.contentView = recorder
        other.makeKeyAndOrderFront(nil)
        other.makeFirstResponder(recorder)
        postEscape(to: other)
        await waitUntil("another window receives its own Escape event") { recorder.escapeCount == 1 }
        check(resultWindow.isVisible && vm.isPinned, "result Escape monitoring does not unpin or close another window's result")
        resultWindow.makeKeyAndOrderFront(nil)
        postEscape(to: resultWindow)
        await waitUntil("Escape in the result panel unpins it") { !vm.isPinned }
        NSApp.activate(ignoringOtherApps: true)
        await waitUntil("the unpinned result window is active before opening details") { NSApp.isActive && resultWindow.isKeyWindow }
        await waitUntil("the real result details button appears in the accessibility tree") {
            self.accessibilityElement(in: resultWindow, matching: {
                $0.accessibilityIdentifier?() == "SnapAI.Result.RequestDetails"
            }) != nil
        }
        guard let detailsButton = accessibilityElement(in: resultWindow, matching: {
            $0.accessibilityIdentifier?() == "SnapAI.Result.RequestDetails"
        }) else {
            failures.append("the visible result window exposes its real details button")
            result.hide()
            other.close()
            return
        }
        postClick(on: detailsButton, in: resultWindow)
        await waitUntil("the unpinned result has a real visible popover") {
            vm.showRouteDetails && self.hasVisiblePopover(in: resultWindow)
        }
        postEscape(to: resultWindow)
        await waitUntil("Escape dismisses the actual request-details popover") {
            !self.hasVisiblePopover(in: resultWindow)
        }
        check(resultWindow.isVisible && !vm.isPinned && !vm.showRouteDetails,
              "Escape dismisses details without closing or pinning the unpinned result window")
        postEscape(to: resultWindow)
        await waitUntil("a subsequent result Escape closes its own panel") { !resultWindow.isVisible }

        let quick = QuickInputController(model: QuickInputModel(settings: settings))
        let priorQuick = Set(NSApp.windows.map(\.windowNumber))
        quick.show()
        guard let quickWindow = NSApp.windows.first(where: { !priorQuick.contains($0.windowNumber) && $0 is FloatingPanel }) else {
            failures.append("the real quick-input controller creates its panel")
            other.close()
            return
        }
        other.makeKeyAndOrderFront(nil)
        other.makeFirstResponder(recorder)
        postEscape(to: other)
        await waitUntil("another window keeps Escape while quick input is open") { recorder.escapeCount == 2 }
        check(quickWindow.isVisible, "quick input does not consume Escape for another window")
        quickWindow.makeKeyAndOrderFront(nil)
        postEscape(to: quickWindow)
        await waitUntil("Escape closes its own quick-input panel") { !quickWindow.isVisible }
        quick.hide()
        result.hide()
        other.close()
    }

    private func postEscape(to window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: window.windowNumber, context: nil,
                                    characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                    isARepeat: false, keyCode: 53)!
        NSApp.postEvent(event, atStart: false)
    }

    private func postClick(on element: AnyObject, in window: NSWindow) {
        guard let frame = element.accessibilityFrame?(), !frame.isEmpty else {
            failures.append("the real details button has a clickable frame")
            return
        }
        let local = window.convertFromScreen(frame)
        let location = NSPoint(x: local.midX, y: local.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1)!
            NSApp.postEvent(event, atStart: false)
        }
    }

    private func hasVisiblePopover(in window: NSWindow) -> Bool {
        accessibilityElement(in: window, matching: { $0.accessibilityRole?() == .popover }) != nil ||
            window.childWindows?.contains(where: { $0.isVisible }) == true
    }

    private func accessibilityElement(in object: Any,
                                      matching predicate: (AnyObject) -> Bool) -> AnyObject? {
        let element = object as AnyObject
        if predicate(element) { return element }
        for child in element.accessibilityChildren?() ?? [] {
            if let found = accessibilityElement(in: child, matching: predicate) { return found }
        }
        return nil
    }

    private func finish() async {
        NSApp.windows.forEach { $0.orderOut(nil) }
        RoutingMetricsStore.shared.flushPersistence()
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        UserDefaults.standard.removePersistentDomain(forName: "com.snapai.runtime-tests")
        let status = failures.isEmpty ? "PASS" : "FAIL"
        let summary = status + " App runtime smoke: VM replacement, drain isolation, cancel/error side effects, history feedback, quick-input acceptance, saved panel sizes, panel/window races, unpinned popover Escape\n"
        try? (summary + failures.map { "FAIL: \($0)\n" }.joined()).write(to: resultURL, atomically: true, encoding: .utf8)
        URLProtocol.unregisterClass(StreamFixtureProtocol.self)
        exit(failures.isEmpty ? 0 : 1)
    }
}

@main
struct AppRuntimeSmokeMain {
    @MainActor static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        guard ProcessInfo.processInfo.environment["SNAPAI_LOGIC_TESTS"] == "1",
              Bundle.main.bundleIdentifier == "com.snapai.runtime-tests",
              let outputIndex = arguments.firstIndex(of: "--results"), arguments.indices.contains(outputIndex + 1),
              let rootIndex = arguments.firstIndex(of: "--fixture-root"), arguments.indices.contains(rootIndex + 1) else {
            fatalError("Run the isolated test bundle with scripts/run-app-runtime-tests.sh")
        }
        _ = URLProtocol.registerClass(StreamFixtureProtocol.self)
        let delegate = AppRuntimeSmokeDelegate(fixtureRoot: URL(fileURLWithPath: arguments[rootIndex + 1]),
                                               resultURL: URL(fileURLWithPath: arguments[outputIndex + 1]))
        let app = NSApplication.shared
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
