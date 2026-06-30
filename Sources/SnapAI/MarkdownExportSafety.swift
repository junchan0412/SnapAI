import Foundation

enum MarkdownExportSafety {
    static func metadata(_ text: String?,
                         fallback: String,
                         maxLength: Int) -> String {
        let raw = text ?? ""
        let cleaned = SensitiveTextSanitizer.sanitizedMessage(raw, limit: max(maxLength, 1))
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "`", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : cleaned
    }

    static func keywords(_ parts: [String?],
                         maxLength: Int = 1_200,
                         partMaxLength: Int = 240) -> String {
        let cleanedParts = parts
            .map { metadata($0, fallback: "", maxLength: max(partMaxLength, 1)) }
            .filter { !$0.isEmpty }
        guard !cleanedParts.isEmpty else { return "" }
        let joined = cleanedParts.joined(separator: " ")
        return SensitiveTextSanitizer.sanitizedMessage(joined, limit: max(maxLength, 1))
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "`", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
