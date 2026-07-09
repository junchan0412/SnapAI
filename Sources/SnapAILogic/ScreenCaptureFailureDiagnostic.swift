import Foundation

public struct ScreenCaptureOutputSnapshot: Equatable {
    public var exists: Bool
    public var byteCount: UInt64?

    public init(exists: Bool, byteCount: UInt64?) {
        self.exists = exists
        self.byteCount = byteCount
    }

    public static let missing = ScreenCaptureOutputSnapshot(exists: false, byteCount: nil)

    public static func make(fileURL: URL,
                            fileManager: FileManager = .default) -> ScreenCaptureOutputSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.uint64Value
        return ScreenCaptureOutputSnapshot(exists: true, byteCount: byteCount)
    }
}

public struct ScreenCaptureFailureDiagnostic: Error, LocalizedError, Equatable {
    public enum Reason: Equatable {
        case missingPermission
        case commandFailed(Int32)
        case outputMissing
        case outputEmpty
        case unreadableOutput
        case invalidImage
        case optimizedImageTooLarge

        public var diagnosticCode: String {
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

        public var exitStatus: Int32? {
            if case .commandFailed(let status) = self {
                return status
            }
            return nil
        }
    }

    public var reason: Reason
    public var permissionGranted: Bool
    public var output: ScreenCaptureOutputSnapshot

    public init(reason: Reason,
                permissionGranted: Bool,
                output: ScreenCaptureOutputSnapshot) {
        self.reason = reason
        self.permissionGranted = permissionGranted
        self.output = output
    }

    public static func missingPermission() -> ScreenCaptureFailureDiagnostic {
        ScreenCaptureFailureDiagnostic(reason: .missingPermission,
                                       permissionGranted: false,
                                       output: .missing)
    }

    public var errorDescription: String? {
        userMessage
    }

    public var userMessage: String {
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

    public var shareableText: String {
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
