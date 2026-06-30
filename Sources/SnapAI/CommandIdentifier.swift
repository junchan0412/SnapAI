import Foundation

enum CommandIdentifier {
    static func uniqued(_ ids: [String]) -> [String] {
        var usedIDs = Set<String>()
        return ids.map { unique(base: $0, usedIDs: &usedIDs) }
    }

    static func unique(base: String, usedIDs: inout Set<String>) -> String {
        let slug = slug(for: base)
        var candidate = slug
        var suffix = 2
        while usedIDs.contains(candidate) {
            candidate = "\(slug)-\(suffix)"
            suffix += 1
        }
        usedIDs.insert(candidate)
        return candidate
    }

    static func unique(prefix: String, values: [String], usedIDs: inout Set<String>) -> String {
        let slug = values.map(Self.slug).joined(separator: "-")
        let base = "\(prefix)-\(slug)"
        var candidate = base
        var suffix = 2
        while usedIDs.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        usedIDs.insert(candidate)
        return candidate
    }

    static func slug(for value: String) -> String {
        var result = ""
        var previousWasSeparator = false
        for scalar in value.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.append(String(scalar))
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "untitled" : trimmed
    }
}
