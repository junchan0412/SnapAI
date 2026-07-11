import Foundation

public struct ResultOperationFeedback: Identifiable, Equatable {
    public enum Kind: Equatable {
        case success
        case warning
    }

    public var id: UUID
    public var message: String
    public var kind: Kind

    public init(id: UUID = UUID(), message: String, kind: Kind) {
        self.id = id
        self.message = message
        self.kind = kind
    }

    public var systemImage: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    public var dismissDelaySeconds: Double {
        switch kind {
        case .success: return 2.2
        case .warning: return 4.5
        }
    }

    public static func success(_ message: String) -> Self {
        Self(message: message, kind: .success)
    }

    public static func warning(_ message: String) -> Self {
        Self(message: message, kind: .warning)
    }
}

public enum ResultExportFilename {
    public static func suggested(actionName: String, timestamp: Int) -> String {
        let forbidden = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "/\\:"))
        let parts = actionName.components(separatedBy: forbidden)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var stem = parts.joined(separator: "-")
        while stem.contains("--") {
            stem = stem.replacingOccurrences(of: "--", with: "-")
        }
        stem = String(stem.prefix(64)).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        if stem.isEmpty { stem = "SnapAI" }
        return "\(stem)-\(max(0, timestamp)).md"
    }
}
