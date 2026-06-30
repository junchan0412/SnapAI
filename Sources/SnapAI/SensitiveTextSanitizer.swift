import Foundation

enum SensitiveTextSanitizer {
    static func sanitizedMessage(_ message: String, limit: Int = 180) -> String {
        let flattened = redactedLocalPaths(redactSensitiveFragments(message))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)) + "..."
    }

    static func sanitizedDiagnosticText(_ message: String, limit: Int = 4_000) -> String {
        let normalized = redactedLocalPaths(redactSensitiveFragments(message))
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                String(line)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        let text = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n..."
    }

    static func redactedLocalPaths(_ message: String,
                                   homeDirectory: String = NSHomeDirectory()) -> String {
        var result = message
        let home = homeDirectory
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !home.isEmpty {
            let normalizedHome = "/" + home
            let escapedHome = NSRegularExpression.escapedPattern(for: normalizedHome)
            result = result.replacingOccurrences(of: escapedHome + #"(?=$|[/\s"'`,;}])"#,
                                                 with: "~",
                                                 options: .regularExpression)
        }
        return result.replacingOccurrences(of: #"(?<![A-Za-z0-9_])/Users/[^/\s"'`,;}]+"#,
                                           with: "/Users/[user]",
                                           options: .regularExpression)
    }

    private static func redactSensitiveFragments(_ message: String) -> String {
        var result = message
        let replacements: [(String, String)] = [
            (#"(?s)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#, "[REDACTED_PRIVATE_KEY]"),
            (#"(?i)\b(authorization\s*[:=]\s*(?:bearer|basic|token)\s+)[^\s"',}]+"#, "$1[REDACTED]"),
            (#"(?i)([?&](?:x-api-key|api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|client[_-]?secret|token|secret|password)=)[^&#\s]+"#, "$1[REDACTED]"),
            (#"(?i)\b(x-api-key|api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password)\s*[:=]\s*["']?[^"'\s,}&]{6,}"#, "$1=[REDACTED]"),
            (#"(?i)"(x-api-key|api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password)"\s*:\s*"[^"]{6,}""#, "\"$1\":\"[REDACTED]\""),
            (#"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b"#, "[REDACTED_JWT]"),
            (#"(?i)\bsk-[A-Za-z0-9_\-]{12,}"#, "[REDACTED_KEY]"),
            (#"\bghp_[A-Za-z0-9_]{20,}\b"#, "[REDACTED_KEY]"),
            (#"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#, "[REDACTED_KEY]"),
            (#"\bxox[baprs]-[A-Za-z0-9\-]{20,}\b"#, "[REDACTED_KEY]"),
            (#"\bAKIA[0-9A-Z]{16}\b"#, "[REDACTED_KEY]"),
            (#"\bAIza[0-9A-Za-z_\-]{20,}\b"#, "[REDACTED_KEY]")
        ]
        for (pattern, template) in replacements {
            result = result.replacingOccurrences(of: pattern,
                                                 with: template,
                                                 options: .regularExpression)
        }
        return result
    }
}
