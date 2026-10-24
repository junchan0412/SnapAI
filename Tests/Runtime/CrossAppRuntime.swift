import AppKit
import ApplicationServices
import Foundation
import SnapAILogic

private enum Fixture {
    static let titleMarker = "SnapAI-CrossApp-Fixture-"
    static let original = "SnapAI fixture source 20261006."
    static let replacement = "SnapAI fixture replacement 20261006."
    static let clipboard = "SnapAI fixture clipboard 20261006."
    static let concurrentClipboard = "SnapAI fixture concurrent clipboard 20261006."
    static let ownerType = NSPasteboard.PasteboardType("com.snapai.cross-app-runtime.owner")
}

private struct Options {
    let bundleID: String
    let pid: pid_t
    let title: String
    let mode: String
    let expected: String
    let stateDirectory: URL?
    let timeout: TimeInterval
    let fixtureName: String
    let activateFixture: Bool
    let alternateFixtureTitle: String?
    var captureOnly: Bool { mode == "ax" || mode == "copy" }
    var usesCopy: Bool { mode == "copy" || mode == "copy-replace" }
    var original: String { fixtureName == "unicode" ? "SnapAI 虚构原文 👩🏽‍💻 e\u{301} 20261006." : Fixture.original }
    var replacement: String { fixtureName == "unicode" ? "SnapAI 虚构替换 🧪 e\u{301} 20261006." : Fixture.replacement }

    static func parse() -> Options? {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count.isMultiple(of: 2) else { return nil }
        let keys: Set<String> = ["--bundle-id", "--pid", "--window-title", "--mode", "--expect", "--state-dir", "--timeout", "--fixture", "--activate-fixture", "--alternate-fixture-title"]
        var values: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let key = arguments[index]
            guard keys.contains(key), values[key] == nil else { return nil }
            values[key] = arguments[index + 1]
        }
        guard let bundleID = values["--bundle-id"], !bundleID.isEmpty,
              let rawPID = values["--pid"], let pid = Int32(rawPID), pid > 0,
              let title = values["--window-title"], title.contains(Fixture.titleMarker),
              let mode = values["--mode"], ["ax", "copy", "copy-replace", "replace", "two-phase"].contains(mode) else { return nil }
        let expected = values["--expect"] ?? "pass"
        guard ["pass", "source-changed", "selection-changed", "target-changed", "validation-unavailable", "pasteboard-changed"].contains(expected),
              mode == "two-phase" || expected == "pass"
                || (expected == "pasteboard-changed" && ["replace", "copy-replace"].contains(mode)) else { return nil }
        let fixtureName = values["--fixture"] ?? "ascii"
        guard ["ascii", "unicode"].contains(fixtureName) else { return nil }
        let activation = values["--activate-fixture"] ?? "false"
        guard ["true", "false"].contains(activation) else { return nil }
        let alternateFixtureTitle = values["--alternate-fixture-title"]
        if let alternateFixtureTitle {
            guard mode == "two-phase", expected == "target-changed",
                  alternateFixtureTitle.contains(Fixture.titleMarker), alternateFixtureTitle != title else { return nil }
        }
        let timeout = TimeInterval(values["--timeout"] ?? "120") ?? 0
        guard timeout >= 1, timeout <= 600 else { return nil }
        let directory = values["--state-dir"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard mode != "two-phase" || directory != nil else { return nil }
        return Options(bundleID: bundleID, pid: pid, title: title, mode: mode,
                       expected: expected, stateDirectory: directory, timeout: timeout,
                       fixtureName: fixtureName, activateFixture: activation == "true",
                       alternateFixtureTitle: alternateFixtureTitle)
    }
}

private struct ClipboardLease {
    let original: PasteboardSnapshot
    var fixture: PasteboardSnapshot
    private var restoredAfterInjectionFailure = false

    @MainActor static func begin() -> ClipboardLease? {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        let original = TextCapture.snapshotPasteboard(pasteboard)
        guard original.canRestore, pasteboard.changeCount == changeCount else { return nil }
        let (item, fixture) = ownedMarker(Fixture.clipboard)
        pasteboard.clearContents()
        let clearedChangeCount = pasteboard.changeCount
        guard pasteboard.writeObjects([item]) else {
            TextCapture.restorePasteboardIfUnchanged(pasteboard, snapshot: original,
                                                     expectedChangeCount: clearedChangeCount)
            return nil
        }
        return ClipboardLease(original: original, fixture: fixture)
    }

    @MainActor mutating func injectConcurrentMarker(expectedChangeCount: Int, replacement: String) -> Bool {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == expectedChangeCount,
              pasteboard.string(forType: .string) == replacement,
              pasteboard.changeCount == expectedChangeCount else { return false }
        let (item, marker) = Self.ownedMarker(Fixture.concurrentClipboard)
        guard pasteboard.changeCount == expectedChangeCount else { return false }
        pasteboard.clearContents()
        let clearedChangeCount = pasteboard.changeCount
        guard pasteboard.writeObjects([item]) else {
            restoredAfterInjectionFailure = TextCapture.restorePasteboardIfUnchanged(
                pasteboard, snapshot: original, expectedChangeCount: clearedChangeCount)
            return false
        }
        fixture = marker
        return true
    }

    @MainActor var ownsCurrentMarker: Bool {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        return TextCapture.snapshotPasteboard(pasteboard) == fixture && pasteboard.changeCount == changeCount
    }

    private static func ownedMarker(_ text: String) -> (NSPasteboardItem, PasteboardSnapshot) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(UUID().uuidString, forType: Fixture.ownerType)
        let data = Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
            item.data(forType: type).map { (type.rawValue, $0) }
        })
        return (item, PasteboardSnapshot.complete(items: [data],
                                                 totalByteCount: data.values.reduce(0) { $0 + $1.count },
                                                 itemCount: 1, typeCount: data.count))
    }

    @MainActor func restore() -> String {
        if restoredAfterInjectionFailure { return "restored-after-injection-failure" }
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard TextCapture.snapshotPasteboard(pasteboard) == fixture,
              pasteboard.changeCount == changeCount else { return "preserved-concurrent-change" }
        return TextCapture.restorePasteboardIfUnchanged(pasteboard, snapshot: original,
                                                        expectedChangeCount: changeCount)
            ? "restored" : "preserved-concurrent-change"
    }
}

@main
private struct CrossAppRuntime {
    @MainActor private static var report: [String: Any] = ["schema": 1, "fixture": "cross-app-20261006"]

    static func main() {
        Task { @MainActor in
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            guard let options = Options.parse() else {
                finish(status: "BLOCKED", reason: "invalid-arguments", code: 2)
            }
            report["mode"] = options.mode
            report["expected"] = options.expected
            report["fixtureVariant"] = options.fixtureName
            report["captureOnly"] = options.captureOnly
            report["transactionAttempted"] = false
            report["activationRequested"] = options.activateFixture
            report["activationInvoked"] = false
            report["alternateFixtureConfigured"] = options.alternateFixtureTitle != nil
            report["triggerEvidence"] = "fixture-runtime-initialization"
            report["expectedSourceUTF16Length"] = options.original.utf16.count
            report["expectedReplacementUTF16Length"] = options.replacement.utf16.count
            guard TextCapture.hasAccessibilityPermission(prompt: false) else {
                finish(status: "BLOCKED", reason: "accessibility-permission-missing", code: 2)
            }
            guard CGPreflightPostEventAccess() else {
                finish(status: "BLOCKED", reason: "post-event-permission-missing", code: 2)
            }
            await run(options)
        }
        CFRunLoopRun()
    }

    @MainActor private static func run(_ options: Options) async {
        if options.activateFixture { await activateFixture(options) }
        if let failure = targetFailure(options) {
            finish(status: "BLOCKED", reason: failure, code: 2)
        }
        guard let targetApp = NSRunningApplication(processIdentifier: options.pid) else {
            finish(status: "BLOCKED", reason: "target-unavailable", code: 2)
        }
        if options.mode == "two-phase", let directory = options.stateDirectory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  !FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready.json").path),
                  !FileManager.default.fileExists(atPath: directory.appendingPathComponent("go").path) else {
                finish(status: "BLOCKED", reason: "state-directory-not-ready", code: 2)
            }
        }
        guard let captureLease = ClipboardLease.begin() else {
            finish(status: "BLOCKED", reason: "pasteboard-snapshot-unsafe-or-changed", code: 2)
        }
        if let failure = targetFailure(options) {
            report["captureClipboard"] = captureLease.restore()
            finish(status: "BLOCKED", reason: failure, code: 2)
        }
        TextCapture.clearRecentSelectionSnapshot()
        let started = Date()
        let outcome: TextCaptureOutcome = await withCheckedContinuation { continuation in
            TextCapture.captureDetailed(preferAX: !options.usesCopy, targetApp: targetApp) {
                continuation.resume(returning: $0)
            }
        }
        report["captureMilliseconds"] = Int(Date().timeIntervalSince(started) * 1_000)
        report["captureClipboard"] = captureLease.restore()
        report["captureMethod"] = outcome.method?.rawValue ?? "none"
        report["accessibilityAttempted"] = outcome.accessibilityAttempted
        report["clipboardAttempted"] = outcome.clipboardAttempted
        report["clipboardWaitAttempts"] = outcome.clipboardWaitAttempts
        report["captureFailure"] = outcome.failureReason?.rawValue ?? "none"
        report["capturedUTF16Length"] = outcome.text?.utf16.count ?? 0
        report["sourceExpectedMatch"] = outcome.text == options.original
        if let failure = targetFailure(options) {
            finish(status: "BLOCKED", reason: failure, code: 2)
        }
        guard outcome.text == options.original else {
            finish(status: "BLOCKED", reason: "fixture-source-mismatch", code: 2)
        }
        guard report["captureClipboard"] as? String == "restored" else {
            finish(status: "BLOCKED", reason: "concurrent-pasteboard-change", code: 2)
        }
        if options.mode == "ax", outcome.method != .accessibility {
            finish(status: "BLOCKED", reason: "ax-fell-back-to-clipboard", code: 2)
        }
        if options.usesCopy, outcome.method != .clipboard {
            finish(status: "FAIL", reason: "copy-path-not-exercised", code: 1)
        }
        let snapshot = TextCapture.recentSelectionSnapshot(matching: options.original)
            ?? TextCapture.selectionSnapshot(matching: options.original, targetApp: targetApp)
        report["selectionSnapshotAvailable"] = snapshot != nil
        if options.captureOnly {
            finish(status: "PASS", reason: "capture-verified", code: 0)
        }
        guard let snapshot,
              let targetSnapshot = TextCapture.writeBackTargetSnapshot(targetPID: options.pid) else {
            finish(status: "BLOCKED", reason: "validation-unavailable", code: 2)
        }
        if let failure = snapshot.validationFailure(original: options.original, targetPID: options.pid) {
            finish(status: "BLOCKED", reason: failure.rawValue, code: 2)
        }
        if options.mode == "two-phase", let directory = options.stateDirectory {
            var ready = report
            ready["phase"] = "ready"
            guard let data = try? JSONSerialization.data(withJSONObject: ready, options: [.sortedKeys]),
                  (try? data.write(to: directory.appendingPathComponent("ready.json"), options: .atomic)) != nil else {
                finish(status: "BLOCKED", reason: "ready-marker-write-failed", code: 2)
            }
            emit(ready)
            let deadline = Date().addingTimeInterval(options.timeout)
            while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("go").path) {
                guard Date() < deadline else {
                    finish(status: "BLOCKED", reason: "go-marker-timeout", code: 2)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        if targetFailure(options, allowsAlternateFixture: true) != nil {
            rejectFixtureBoundary(options)
        }
        report["snapshotValidationBeforeTransaction"] = snapshot.validationFailure(
            original: options.original, targetPID: options.pid)?.rawValue ?? "none"
        guard var replacementLease = ClipboardLease.begin() else {
            finish(status: "BLOCKED", reason: "pasteboard-snapshot-unsafe-or-changed", code: 2)
        }
        if targetFailure(options, allowsAlternateFixture: true) != nil {
            report["replacementClipboard"] = replacementLease.restore()
            rejectFixtureBoundary(options)
        }
        report["transactionAttempted"] = true
        report["transactionFixtureRole"] = report["focusedFixtureRole"]
        report["alternateFixtureWasTransactionTarget"] = options.alternateFixtureTitle != nil
            && report["focusedFixtureRole"] as? String == "alternate"
        let focusedBeforeTransaction = elementAttribute(kAXFocusedUIElementAttribute, in: AXUIElementCreateSystemWide())
        let fixtureTextBeforeTransaction = focusedBeforeTransaction.flatMap { attribute(kAXValueAttribute, in: $0) as? String }
        var targetGateRejected = false
        var targetGateChecks = 0
        let transaction = TextEditTransaction(targetApp: targetApp, selectionSnapshot: snapshot,
                                              confirmedTargetSnapshot: targetSnapshot,
                                              additionalTargetValidation: {
            targetGateChecks += 1
            guard targetFailure(options, allowsAlternateFixture: true) == nil else {
                targetGateRejected = true
                return .targetChanged
            }
            return nil
        })
        let replacementStarted = Date()
        var transactionFinished = false
        var concurrentMarkerInjected = false
        let result: String = await withCheckedContinuation { continuation in
            transaction.replace(original: options.original, with: options.replacement) {
                transactionFinished = true
                continuation.resume(returning: "completed")
            } failure: { _ in
                transactionFinished = true
                continuation.resume(returning: "pasteboard-snapshot-unsafe")
            } validationFailure: { reason in
                transactionFinished = true
                continuation.resume(returning: reason.rawValue)
            }
            if options.expected == "pasteboard-changed", !transactionFinished {
                let transactionChangeCount = NSPasteboard.general.changeCount
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard !transactionFinished else { return }
                    concurrentMarkerInjected = replacementLease.injectConcurrentMarker(
                        expectedChangeCount: transactionChangeCount, replacement: options.replacement)
                }
            }
        }
        report["replacementMilliseconds"] = Int(Date().timeIntervalSince(replacementStarted) * 1_000)
        report["targetGateChecks"] = targetGateChecks
        report["targetGateRejected"] = targetGateRejected
        report["concurrentMarkerInjected"] = concurrentMarkerInjected
        let concurrentMarkerPreserved = concurrentMarkerInjected && replacementLease.ownsCurrentMarker
        report["concurrentMarkerPreservedByTransaction"] = concurrentMarkerPreserved
        report["replacementClipboard"] = replacementLease.restore()
        report["transactionResult"] = result
        report["businessRejectionVerified"] = false
        if targetGateRejected {
            report["rejectionStage"] = "fixture-target-gate-inside-transaction"
            finish(status: "REJECTED", reason: "target-changed", code: 3)
        }
        if options.expected == "pasteboard-changed", !concurrentMarkerInjected {
            finish(status: "BLOCKED", reason: "concurrent-fixture-injection-not-performed", code: 2)
        }
        guard report["replacementClipboard"] as? String == "restored" else {
            finish(status: "BLOCKED", reason: "concurrent-pasteboard-change", code: 2)
        }
        guard result == "completed" else {
            let postconditionTargetMatches = targetFailure(options, allowsAlternateFixture: true,
                                                           requiresAlternateSelection: false) == nil
            if options.alternateFixtureTitle != nil, !postconditionTargetMatches {
                report["postconditionTargetGateRejected"] = true
                report["rejectionStage"] = "fixture-target-gate-after-transaction"
                finish(status: "REJECTED", reason: "target-changed", code: 3)
            }
            let fixtureTextAfterTransaction = postconditionTargetMatches
                ? focusedBeforeTransaction.flatMap { attribute(kAXValueAttribute, in: $0) as? String } : nil
            let textUnchanged: Bool? = fixtureTextBeforeTransaction.flatMap { before in
                fixtureTextAfterTransaction.map { before == $0 }
            }
            report["rejectionFocusedValuePostcondition"] = textUnchanged.map { $0 ? "unchanged" : "changed" } ?? "unavailable"
            report["rejectionEvidence"] = "transaction-validation-callback-and-clipboard"
            if textUnchanged == false {
                finish(status: "FAIL", reason: "fixture-text-changed-despite-rejection", code: 1)
            }
            if options.alternateFixtureTitle != nil, textUnchanged == nil {
                finish(status: "BLOCKED", reason: "alternate-fixture-postcondition-unavailable", code: 2)
            }
            let expectedMatch = result == options.expected
                && (options.expected != "pasteboard-changed" || concurrentMarkerPreserved)
            report["rejectionStage"] = "real-transaction-validation"
            report["rejectionExpectedMatch"] = expectedMatch
            report["businessRejectionVerified"] = expectedMatch
            finish(status: expectedMatch ? "PASS" : "REJECTED", reason: result, code: expectedMatch ? 0 : 3)
        }
        let verified = targetFailure(options) == nil
            && snapshot.snapshotAfterReplacement(options.replacement, targetPID: options.pid) != nil
        report["replacementExpectedMatch"] = verified
        guard options.expected == "pass" else {
            finish(status: "FAIL", reason: "expected-rejection-not-observed", code: 1)
        }
        guard verified else {
            finish(status: "FAIL", reason: "replacement-postcondition-unverified", code: 1)
        }
        finish(status: "PASS", reason: "replacement-verified", code: 0)
    }

    @MainActor private static func activateFixture(_ options: Options) async {
        let app = NSRunningApplication(processIdentifier: options.pid)
        let processMatches = app?.isTerminated == false && app?.bundleIdentifier == options.bundleID
        var gate: [String: Bool] = [
            "processExists": app != nil,
            "processRunning": app?.isTerminated == false,
            "bundleMatches": app?.bundleIdentifier == options.bundleID,
            "focusedWindowKnown": false,
            "focusedWindowTitleMatches": false,
            "focusedElementKnown": false,
            "focusedElementPIDMatches": false,
            "focusedElementWindowMatches": false,
            "selectedTextReadable": false,
            "selectedTextExpectedMatch": false,
        ]
        guard processMatches, let app else {
            report["activationGate"] = gate
            finish(status: "BLOCKED", reason: "activation-fixture-gate-mismatch", code: 2)
        }
        let appElement = AXUIElementCreateApplication(options.pid)
        let window = elementAttribute(kAXFocusedWindowAttribute, in: appElement)
        let focused = elementAttribute(kAXFocusedUIElementAttribute, in: appElement)
        gate["focusedWindowKnown"] = window != nil
        gate["focusedWindowTitleMatches"] = window.flatMap { attribute(kAXTitleAttribute, in: $0) as? String } == options.title
        gate["focusedElementKnown"] = focused != nil
        if let focused {
            var focusedPID: pid_t = 0
            gate["focusedElementPIDMatches"] = AXUIElementGetPid(focused, &focusedPID) == .success && focusedPID == options.pid
            if let window, let focusedWindow = elementAttribute(kAXWindowAttribute, in: focused) {
                gate["focusedElementWindowMatches"] = CFEqual(window, focusedWindow)
            }
            let selected = attribute(kAXSelectedTextAttribute, in: focused) as? String
            gate["selectedTextReadable"] = selected != nil
            gate["selectedTextExpectedMatch"] = selected == options.original
        }
        report["activationGate"] = gate
        guard gate.values.allSatisfy({ $0 }) else {
            finish(status: "BLOCKED", reason: "activation-fixture-gate-mismatch", code: 2)
        }
        report["activationInvoked"] = true
        report["activationRequestAccepted"] = app.activate()
        let started = Date()
        let deadline = started.addingTimeInterval(2)
        while Date() < deadline {
            if targetFailure(options) == nil {
                report["activationGlobalGatePassed"] = true
                report["activationWaitMilliseconds"] = Int(Date().timeIntervalSince(started) * 1_000)
                return
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(min(0.05, remaining) * 1_000_000_000))
            }
        }
        report["activationGlobalGatePassed"] = false
        report["activationWaitMilliseconds"] = Int(Date().timeIntervalSince(started) * 1_000)
        finish(status: "BLOCKED", reason: "activation-global-gate-timeout", code: 2)
    }

    @MainActor private static func targetFailure(_ options: Options,
                                                allowsAlternateFixture: Bool = false,
                                                requiresAlternateSelection: Bool = true) -> String? {
        report["focusedFixtureRole"] = "unavailable"
        let app = NSRunningApplication(processIdentifier: options.pid)
        let frontmost = NSWorkspace.shared.frontmostApplication
        report["targetIdentity"] = [
            "processExists": app != nil,
            "processRunning": app?.isTerminated == false,
            "bundleMatches": app?.bundleIdentifier == options.bundleID,
            "frontmostKnown": frontmost != nil,
            "frontmostMatches": frontmost?.processIdentifier == options.pid,
        ]
        guard let app, !app.isTerminated,
              app.bundleIdentifier == options.bundleID,
              frontmost?.processIdentifier == options.pid else {
            return "target-identity-mismatch"
        }
        let appElement = AXUIElementCreateApplication(options.pid)
        guard let window = elementAttribute(kAXFocusedWindowAttribute, in: appElement),
              let title = attribute(kAXTitleAttribute, in: window) as? String else {
            return "fixture-window-unavailable"
        }
        let isPrimary = title == options.title
        let isAlternate = allowsAlternateFixture && title == options.alternateFixtureTitle
        report["focusedFixtureRole"] = isPrimary ? "primary" : (isAlternate ? "alternate" : "unowned")
        guard isPrimary || isAlternate else { return "fixture-window-title-mismatch" }
        guard let focused = elementAttribute(kAXFocusedUIElementAttribute, in: AXUIElementCreateSystemWide()) else {
            return "focused-element-unavailable"
        }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success, focusedPID == options.pid else {
            return "focused-element-target-mismatch"
        }
        if let focusedWindow = elementAttribute(kAXWindowAttribute, in: focused), !CFEqual(window, focusedWindow) {
            return "focused-element-window-mismatch"
        }
        if allowsAlternateFixture, options.alternateFixtureTitle != nil, requiresAlternateSelection {
            let selected = attribute(kAXSelectedTextAttribute, in: focused) as? String
            report["alternateFixtureSelectionReadable"] = selected != nil
            report["alternateFixtureSelectionExpectedMatch"] = selected == options.original
            guard selected == options.original else { return "alternate-fixture-selection-mismatch" }
        }
        return nil
    }

    private static func attribute(_ name: String, in element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func elementAttribute(_ name: String, in element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, in: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    @MainActor private static func rejectFixtureBoundary(_ options: Options) -> Never {
        report["rejectionStage"] = "fixture-target-gate"
        report["rejectionExpectedMatch"] = options.expected == "target-changed"
        report["businessRejectionVerified"] = false
        finish(status: "REJECTED", reason: "target-changed", code: 3)
    }

    @MainActor private static func finish(status: String, reason: String, code: Int32) -> Never {
        report["status"] = status
        report["reason"] = reason
        TextCapture.clearRecentSelectionSnapshot()
        emit(report)
        exit(code)
    }

    private static func emit(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
            fflush(stdout)
        }
    }
}
