import AppKit
import ApplicationServices
import Foundation
import SnapAILogic
import SwiftUI

@MainActor
private final class WindowLatencyDelegate: NSObject, NSApplicationDelegate {
    private let outputURL: URL
    private let fixtureRoot: URL
    private let count: Int
    private let suite = "com.snapai.window-latency.\(UUID().uuidString)"
    private var updates: [Int: Int] = [:]
    private var observer: NSObjectProtocol?
    private var samples: [[String: Any]] = []
    private var failures: [String] = []
    private let heading = "WINDOW LATENCY READY"
    private var document: String {
        "## \(heading)\n\n可读结果包含 **粗体** 与 `inline code`。\n\n```swift\nlet answer = 42\nprint(answer)\n```"
    }

    init(outputURL: URL, fixtureRoot: URL, count: Int) {
        self.outputURL = outputURL
        self.fixtureRoot = fixtureRoot
        self.count = count
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .aqua)
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let window = note.object as? NSWindow {
                    self?.updates[window.windowNumber, default: 0] += 1
                }
            }
        }
        Task { @MainActor in
            await run()
            finish()
            NSApp.terminate(nil)
        }
    }

    private func makeSettings() -> AppSettings {
        let settings = AppSettings()
        settings.persistenceDefaults = UserDefaults(suiteName: suite)!
        settings.persistenceHistoryStore = HistoryStore(url: fixtureRoot.appendingPathComponent("history.sqlite"))
        settings.providers = [AIProvider(id: "window-fixture", name: "Offline fixture",
                                         baseURL: "http://127.0.0.1:9/v1", apiKey: "fixture-only",
                                         models: [AIModelEntry(name: "fixture-model")])]
        settings.activeProviderID = "window-fixture"
        settings.activeModel = "fixture-model"
        settings.actions = [AIAction(name: "Window latency", prompt: "{{text}}", saveHistory: false)]
        settings.typewriterSpeed = .off
        settings.iCloudSyncEnabled = false
        settings.onboardingDone = true
        settings.resultPanelDismissMode = .alwaysKeep
        settings.panelWidth = 640
        settings.panelHeight = 640
        return settings
    }

    private func run() async {
        let settings = makeSettings()
        for surface in ["quick", "result"] {
            for mode in ["first-window", "reused-window"] {
                var quick: QuickInputController?
                var result: FloatingPanelController?
                var vm: ResultViewModel?
                var previousWindow: NSWindow?
                let iterations = mode == "reused-window" ? Array(0...count) : Array(1...count)
                for iteration in iterations {
                    if mode == "first-window" || iteration == 0 {
                        if surface == "quick" {
                            quick = QuickInputController(model: QuickInputModel(settings: settings))
                        } else {
                            let model = ResultViewModel(settings: settings)
                            model.action = settings.actions[0]
                            model.sourceText = "固定离线完成态回答，用于测量打开结果窗。"
                            model.activeProviderName = "Offline fixture"
                            model.activeModelName = "fixture-model"
                            _ = model.streamingCoordinator.appendContentToken(document, extractsThinkTags: false)
                            model.output = document
                            model.outputState.flush()
                            vm = model
                            result = FloatingPanelController(vm: model)
                        }
                    }
                    let oldWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
                    let updateBaseline = updates
                    let started = ProcessInfo.processInfo.systemUptime
                    if let quick { quick.show() } else { result?.show() }
                    let showReturned = ProcessInfo.processInfo.systemUptime
                    guard let window = NSApp.windows.first(where: { window in
                        guard window.isVisible else { return false }
                        if let quick {
                            return (window.contentView as? NSHostingView<QuickInputView>)?.rootView.model === quick.model
                        }
                        guard let vm else { return false }
                        return (window.contentView as? NSHostingView<ResultView>)?.rootView.vm === vm
                    }) else {
                        failures.append("\(surface)/\(mode)/\(iteration): show produced no fixture window")
                        return
                    }
                    let reused = oldWindows.contains(ObjectIdentifier(window))
                    if (mode == "first-window" && reused)
                        || (mode == "reused-window" && iteration > 0 && window !== previousWindow) {
                        failures.append("\(surface)/\(mode)/\(iteration): unexpected window identity")
                        return
                    }
                    var sample = await measure(window: window, quick: quick, started: started,
                                               updateBaseline: updateBaseline[window.windowNumber, default: 0])
                    sample["surface"] = surface
                    sample["mode"] = mode
                    sample["iteration"] = iteration
                    sample["warmup"] = iteration == 0
                    sample["show_synchronous_ms"] = (showReturned - started) * 1_000
                    sample["window_number"] = window.windowNumber
                    sample["reused_window"] = reused
                    samples.append(sample)
                    if sample["success"] as? Bool != true {
                        failures.append("\(surface)/\(mode)/\(iteration): readiness deadline exceeded")
                        return
                    }
                    if let quick { quick.hide() } else { result?.hide() }
                    let hiddenDeadline = ProcessInfo.processInfo.systemUptime + 2
                    while window.isVisible && ProcessInfo.processInfo.systemUptime < hiddenDeadline {
                        try? await Task.sleep(nanoseconds: 5_000_000)
                    }
                    guard !window.isVisible else {
                        failures.append("\(surface)/\(mode)/\(iteration): hide did not finish")
                        return
                    }
                    previousWindow = window
                    if mode == "first-window" || iteration == count {
                        window.isReleasedWhenClosed = false
                        window.contentView = nil
                        window.close()
                        quick = nil
                        result = nil
                        vm = nil
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                _ = vm
            }
        }
    }

    private func measure(window: NSWindow, quick: QuickInputController?, started: Double,
                         updateBaseline: Int) async -> [String: Any] {
        var probes = 0
        var probeTime = 0.0
        var visibleAt: Double?
        var inputAcceptedAt: Double?
        var candidateAt: Double?
        var candidateUpdateCount: Int?
        var interactionReadyAt: Double?
        var interactionReadyUpdateCount: Int?
        var fullyVisibleCandidateAt: Double?
        var fullyVisibleProbeCount = 0
        var evidence: [String: Any] = [:]
        var inserted = false
        let expectedText = (quick?.model.text ?? "") + "x"
        let deadline = started + 8
        while ProcessInfo.processInfo.systemUptime < deadline {
            // Yield to AppKit drawing and SwiftUI tasks; never force layout/display or assign focus.
            try? await Task.sleep(nanoseconds: 2_000_000)
            let probeStarted = ProcessInfo.processInfo.systemUptime
            probes += 1
            let visible = window.isVisible && window.occlusionState.contains(.visible)
                && window.alphaValue > 0 && window.contentView?.bounds.isEmpty == false
            if visible && visibleAt == nil { visibleAt = probeStarted }
            var ready = false
            if visible, let quick {
                if let editor = window.firstResponder as? PlaceholderTextView,
                   editor.window === window, editor.isEditable, editor.acceptsFirstResponder,
                   !editor.visibleRect.isEmpty, window.isKeyWindow {
                    if !inserted {
                        editor.insertText("x", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
                        inserted = true
                    }
                    ready = quick.model.text == expectedText && editor.string == expectedText
                    if ready && inputAcceptedAt == nil { inputAcceptedAt = ProcessInfo.processInfo.systemUptime }
                    evidence = ["first_responder": String(describing: type(of: editor)),
                                "editable": editor.isEditable, "model_accepted_inserted_character": ready]
                }
            } else if visible {
                evidence = markdownEvidence(window: window)
                ready = evidence["rendered_markdown_visible"] as? Bool == true
            }
            let updateCount = updates[window.windowNumber, default: 0] - updateBaseline
            if ready && candidateUpdateCount == nil {
                candidateUpdateCount = updateCount
                candidateAt = ProcessInfo.processInfo.systemUptime
            }
            if ready && updateCount > (candidateUpdateCount ?? updateCount) && interactionReadyAt == nil {
                interactionReadyAt = ProcessInfo.processInfo.systemUptime
                interactionReadyUpdateCount = updateCount
            }
            let fullyVisible = ready && interactionReadyAt != nil && window.alphaValue >= 0.99
            if fullyVisible {
                fullyVisibleProbeCount += 1
                if fullyVisibleCandidateAt == nil {
                    fullyVisibleCandidateAt = ProcessInfo.processInfo.systemUptime
                }
            } else {
                fullyVisibleProbeCount = 0
                fullyVisibleCandidateAt = nil
            }
            ready = fullyVisible && fullyVisibleProbeCount >= 2
            let now = ProcessInfo.processInfo.systemUptime
            probeTime += now - probeStarted
            if ready || now >= deadline {
                var sample: [String: Any] = ["success": ready, "elapsed_ms": (now - started) * 1_000,
                    "probe_count": probes, "probe_total_ms": probeTime * 1_000,
                    "window_update_count": updateCount, "window_visible": visible,
                    "fully_visible_consecutive_probes": fullyVisibleProbeCount,
                    "key_window": window.isKeyWindow, "alpha_value": window.alphaValue,
                    "window_frame": NSStringFromRect(window.frame), "evidence": evidence]
                if let visibleAt { sample["visible_ms"] = (visibleAt - started) * 1_000 }
                if let inputAcceptedAt { sample["input_accepted_ms"] = (inputAcceptedAt - started) * 1_000 }
                if let candidateAt { sample["readiness_candidate_ms"] = (candidateAt - started) * 1_000 }
                if let candidateUpdateCount { sample["readiness_candidate_window_update_count"] = candidateUpdateCount }
                if let interactionReadyAt { sample["interaction_ready_ms"] = (interactionReadyAt - started) * 1_000 }
                if let interactionReadyUpdateCount { sample["interaction_ready_window_update_count"] = interactionReadyUpdateCount }
                if let fullyVisibleCandidateAt { sample["fully_visible_candidate_ms"] = (fullyVisibleCandidateAt - started) * 1_000 }
                return sample
            }
        }
        return ["success": false, "elapsed_ms": (ProcessInfo.processInfo.systemUptime - started) * 1_000,
                "probe_count": probes, "probe_total_ms": probeTime * 1_000, "evidence": evidence]
    }

    private func markdownEvidence(window: NSWindow) -> [String: Any] {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let windows = axValue(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let root = windows.first(where: { axValue($0, kAXTitleAttribute) as? String == window.title }),
              let content = window.contentView else { return ["rendered_markdown_visible": false] }
        let scrolls = descendantScrolls(content)
        guard let viewport = scrolls.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else {
            return ["rendered_markdown_visible": false]
        }
        let screenRect = window.convertToScreen(viewport.convert(viewport.contentView.frame, to: nil))
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let axViewport = CGRect(x: screenRect.minX, y: screenTop - screenRect.maxY,
                                width: screenRect.width, height: screenRect.height)
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        var titleFrame: CGRect?
        var codeFrame: CGRect?
        while let (element, depth) = pending.popLast(), visited < 1_024 {
            visited += 1
            guard depth < 64 else { continue }
            let labels = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
                .compactMap { axValue(element, $0) as? String }
            let isHeading = labels.contains(heading)
            let isCode = labels.contains("复制代码块")
                && axValue(element, kAXRoleAttribute) as? String == kAXButtonRole
            if (isHeading || isCode), let frame = axFrame(element), !frame.isEmpty,
               axViewport.insetBy(dx: -1, dy: -1).contains(frame) {
                if isHeading { titleFrame = frame }
                if isCode { codeFrame = frame }
            }
            if titleFrame != nil && codeFrame != nil { break }
            for child in axValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                pending.append((child, depth + 1))
            }
        }
        var evidence: [String: Any] = ["rendered_markdown_visible": titleFrame != nil && codeFrame != nil,
                                      "ax_nodes_visited": visited, "viewport_ax_frame": NSStringFromRect(axViewport)]
        if let titleFrame { evidence["heading_ax_frame"] = NSStringFromRect(titleFrame) }
        if let codeFrame { evidence["code_copy_button_ax_frame"] = NSStringFromRect(codeFrame) }
        return evidence
    }

    private func descendantScrolls(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(descendantScrolls)
    }

    private func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = axValue(element, kAXPositionAttribute),
              let size = axValue(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func finish() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        UserDefaults.standard.removePersistentDomain(forName: suite)
        var groups: [[String: Any]] = []
        for surface in ["quick", "result"] {
            for mode in ["first-window", "reused-window"] {
                let values = samples.filter {
                    $0["surface"] as? String == surface && $0["mode"] as? String == mode
                        && $0["warmup"] as? Bool == false && $0["success"] as? Bool == true
                }.compactMap { $0["elapsed_ms"] as? Double }.sorted()
                var group: [String: Any] = ["surface": surface, "mode": mode, "successful_samples": values.count]
                if values.count == count {
                    group["p50_ms"] = values[Int(ceil(0.50 * Double(values.count))) - 1]
                    group["p95_ms"] = values[Int(ceil(0.95 * Double(values.count))) - 1]
                }
                groups.append(group)
            }
        }
        let payload: [String: Any] = [
            "status": failures.isEmpty ? "PASS" : "FAIL", "failures": failures,
            "requested_samples_per_group": count, "samples": samples, "groups": groups,
            "method": [
                "clock": "ProcessInfo.systemUptime (monotonic)", "poll_interval_ms": 2,
                "start": "immediately before the real controller.show(); models/controllers and completed fixture are prepared beforehand",
                "first_window": "new controller and new NSHostingView/NSPanel per sample, same process; OS/framework caches remain warm; not OS cold start",
                "reused_window": "one excluded first-show warmup then reopen the same controller/window/hosting tree and same completed Markdown",
                "quick_endpoint": "visible/unoccluded key panel, editable PlaceholderTextView firstResponder; insertText accepted by editor and model, then a subsequent NSWindow didUpdate; final elapsed_ms requires all input evidence plus alphaValue >= 0.99 on two consecutive probes",
                "result_endpoint": "visible/unoccluded panel; exact rendered heading plus Markdown-only code-copy button have nonempty AX frames fully inside actual scroll viewport, then a subsequent NSWindow didUpdate; final elapsed_ms requires all Markdown evidence plus alphaValue >= 0.99 on two consecutive probes",
                "intermediate_timestamps": "readiness_candidate_ms is first input/Markdown evidence regardless of fade; interaction_ready_ms additionally waits for a subsequent didUpdate; fully_visible_candidate_ms requires interaction readiness and alphaValue >= 0.99; final elapsed_ms rechecks every condition on the next consecutive probe. Content-update evidence precedes the fade threshold: no extra didUpdate is required after fade completion because AppKit does not guarantee one",
                "fully_visible_alpha_threshold": 0.99,
                "fully_visible_required_consecutive_probes": 2,
                "observer": "same-process AX queries; measured probe overhead remains included in elapsed_ms and is reported separately; no forced focus/layout/display",
                "limits": "controller-dispatch to UI readiness with the 0.99 window-alpha threshold; excludes hardware input/hotkey routing, OS launch, AI network/streaming and GPU/compositor scanout; no FPS claim",
                "percentile": "nearest-rank ceil(p*n)-1; only emitted for a complete group"
            ],
            "runtime": ["process_id": ProcessInfo.processInfo.processIdentifier,
                         "system_uptime_at_finish_seconds": ProcessInfo.processInfo.systemUptime,
                         "reduce_motion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                         "reduce_transparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                         "appearance": "aqua", "fixture_markdown": document,
                         "fixture_characters": document.count, "network": "none; completed fixture only",
                         "screens": NSScreen.screens.map { ["frame": NSStringFromRect($0.frame),
                                                            "visible_frame": NSStringFromRect($0.visibleFrame),
                                                            "backing_scale": $0.backingScaleFactor] as [String: Any] }]
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputURL, options: .atomic)
        } catch {
            fputs("window benchmark result write failed: \(error)\n", stderr)
        }
    }
}

@main
private struct WindowLatencyBenchmarks {
    @MainActor static func main() {
        let args = ProcessInfo.processInfo.arguments
        guard args.count == 4, let count = Int(args[3]), (1...100).contains(count) else {
            fputs("usage: WindowLatencyBenchmarks results.json fixture-directory samples\n", stderr)
            return
        }
        let application = NSApplication.shared
        let delegate = WindowLatencyDelegate(outputURL: URL(fileURLWithPath: args[1]),
                                             fixtureRoot: URL(fileURLWithPath: args[2]), count: count)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
