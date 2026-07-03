import Foundation

struct ScreenCaptureOutputSnapshot: Equatable {
    var exists: Bool
    var byteCount: UInt64?

    static let missing = ScreenCaptureOutputSnapshot(exists: false, byteCount: nil)

    static func make(fileURL: URL,
                     fileManager: FileManager = .default) -> ScreenCaptureOutputSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.uint64Value
        return ScreenCaptureOutputSnapshot(exists: true, byteCount: byteCount)
    }
}

struct ScreenCaptureFailureDiagnostic: Error, LocalizedError, Equatable {
    enum Reason: Equatable {
        case missingPermission
        case commandFailed(Int32)
        case outputMissing
        case outputEmpty
        case unreadableOutput
        case invalidImage
        case optimizedImageTooLarge

        var diagnosticCode: String {
            switch self {
            case .missingPermission:
                return "missing-permission"
            case .commandFailed:
                return "command-failed"
            case .outputMissing:
                return "output-missing"
            case .outputEmpty:
                return "output-empty"
            case .unreadableOutput:
                return "unreadable-output"
            case .invalidImage:
                return "invalid-image"
            case .optimizedImageTooLarge:
                return "optimized-image-too-large"
            }
        }

        var exitStatus: Int32? {
            if case .commandFailed(let status) = self {
                return status
            }
            return nil
        }
    }

    var reason: Reason
    var permissionGranted: Bool
    var output: ScreenCaptureOutputSnapshot

    static func missingPermission() -> ScreenCaptureFailureDiagnostic {
        ScreenCaptureFailureDiagnostic(reason: .missingPermission,
                                       permissionGranted: false,
                                       output: .missing)
    }

    var errorDescription: String? {
        userMessage
    }

    var userMessage: String {
        switch reason {
        case .missingPermission:
            return ScreenCapturePermission.recoveryMessage
        case .commandFailed(let status):
            return "系统截图命令返回退出码 \(status)。\(ScreenCapturePermission.recoveryMessage)"
        case .outputMissing:
            return "系统截图命令没有生成图片文件。\(ScreenCapturePermission.recoveryMessage)"
        case .outputEmpty:
            return "系统截图生成了空图片文件。\(ScreenCapturePermission.recoveryMessage)"
        case .unreadableOutput:
            return "截图文件无法读取。请重试；如果持续失败，请复制诊断信息排查。"
        case .invalidImage:
            return "截图文件无法解析为图片。请重试；如果持续失败，请复制诊断信息排查。"
        case .optimizedImageTooLarge:
            return "截图压缩后仍超过 AI 请求体限制。请截取更小区域,或裁剪图片后重试。"
        }
    }

    var shareableText: String {
        [
            "SnapAI Screen Capture Diagnostic",
            "Reason: \(reason.diagnosticCode)",
            "Permission Granted: \(permissionGranted ? "yes" : "no")",
            "Command Exit Status: \(reason.exitStatus.map(String.init) ?? "none")",
            "Output File Exists: \(output.exists ? "yes" : "no")",
            "Output File Bytes: \(output.byteCount.map(String.init) ?? "unknown")",
            "Recovery: \(ScreenCapturePermission.recoveryMessage)"
        ].joined(separator: "\n")
    }
}
