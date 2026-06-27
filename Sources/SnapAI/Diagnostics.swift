import AppKit
import ApplicationServices
import Foundation

struct PermissionHealthSnapshot {
    var appVersion: String
    var macOSVersion: String
    var bundleID: String
    var installPath: String
    var accessibilityGranted: Bool
    var screenCaptureGranted: Bool
    var launchAtLogin: Bool
    var showDockIcon: Bool
    var signingSummary: String
    var hotKeyFailures: [String]
    var activeModel: String
    var providerCount: Int

    var diagnosticText: String {
        """
        SnapAI Diagnostics
        Version: \(appVersion)
        macOS: \(macOSVersion)
        Bundle ID: \(bundleID)
        Install Path: \(installPath)
        Accessibility: \(accessibilityGranted ? "granted" : "missing")
        Screen Recording: \(screenCaptureGranted ? "granted" : "missing")
        Launch At Login: \(launchAtLogin ? "enabled" : "disabled")
        Dock Icon: \(showDockIcon ? "visible" : "hidden")
        Active Model: \(activeModel)
        Providers: \(providerCount)
        Signing: \(signingSummary)
        HotKey Failures: \(hotKeyFailures.isEmpty ? "none" : hotKeyFailures.joined(separator: "; "))
        """
    }

    static func make(settings: AppSettings, hotKeyFailures: [String]) -> PermissionHealthSnapshot {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let installPath = Bundle.main.bundleURL.path
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let active = [settings.activeProvider?.name ?? "", settings.activeModel]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        return PermissionHealthSnapshot(
            appVersion: version,
            macOSVersion: os,
            bundleID: bundleID,
            installPath: installPath,
            accessibilityGranted: TextCapture.hasAccessibilityPermission(),
            screenCaptureGranted: CGPreflightScreenCaptureAccess(),
            launchAtLogin: LoginItem.isEnabled,
            showDockIcon: settings.showDockIcon,
            signingSummary: signingSummary(for: Bundle.main.bundleURL),
            hotKeyFailures: hotKeyFailures,
            activeModel: active.isEmpty ? "未选择" : active,
            providerCount: settings.providers.count
        )
    }

    private static func signingSummary(for appURL: URL) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        proc.arguments = ["-dv", "--verbose=4", appURL.path]
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe
        do {
            try proc.run()
            // 先读完管道再等待退出,避免输出填满缓冲区时死锁
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            let requirement = text
                .split(separator: "\n")
                .map(String.init)
                .first { $0.hasPrefix("designated =>") }
                .map { String($0.dropFirst("designated =>".count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            var lines = text
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("Authority=") || $0.hasPrefix("TeamIdentifier=") || $0.hasPrefix("CDHash=") }
            if let requirement {
                lines.append("Requirement=\(requirement)")
            }
            return lines.isEmpty ? "未获取到签名详情" : lines.joined(separator: ", ")
        } catch {
            return "签名检查失败: \(error.localizedDescription)"
        }
    }
}
