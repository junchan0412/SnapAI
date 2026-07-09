import Foundation

public enum CommandPaletteMatcher {
    private static let querySeparators: Set<Character> = [
        "+", "-", "_", "/", "\\", ",", ".", ":", ";", "|",
        "(", ")", "[", "]", "{", "}", "\"", "'",
        "，", "。", "、", "：", "；", "｜",
        "（", "）", "【", "】", "《", "》", "「", "」", "『", "』",
        "！", "？", "“", "”", "‘", "’", "—", "…", "·", "～"
    ]

    private struct RankedItem<T> {
        var index: Int
        var item: T
        var score: Int
    }

    public static func matches(title: String,
                               subtitle: String,
                               keywords: String,
                               query: String) -> Bool {
        score(title: title, subtitle: subtitle, keywords: keywords, query: query) != nil
    }

    public static func score(title: String,
                             subtitle: String,
                             keywords: String,
                             query: String) -> Int? {
        let terms = normalizedTerms(query)
        guard !terms.isEmpty else { return 0 }

        let title = title.lowercased()
        let subtitle = subtitle.lowercased()
        let keywords = keywords.lowercased()
        let searchable = "\(title) \(subtitle) \(keywords)"
        let titleCompact = compactSearchText(title)
        let subtitleCompact = compactSearchText(subtitle)
        let keywordsCompact = compactSearchText(keywords)
        let searchableCompact = "\(titleCompact) \(subtitleCompact) \(keywordsCompact)"

        var total = 0
        for term in terms {
            let compactTerm = compactSearchText(term)
            guard searchable.contains(term) || searchableCompact.contains(compactTerm) else { return nil }
            if title == term {
                total += 120
            } else if title.hasPrefix(term) {
                total += 90
            } else if title.contains(term) {
                total += 70
            } else if !compactTerm.isEmpty, titleCompact.hasPrefix(compactTerm) {
                total += 60
            } else if !compactTerm.isEmpty, titleCompact.contains(compactTerm) {
                total += 50
            } else if subtitle.hasPrefix(term) {
                total += 45
            } else if subtitle.contains(term) {
                total += 35
            } else if !compactTerm.isEmpty, subtitleCompact.contains(compactTerm) {
                total += 30
            } else if keywords.contains(term) {
                total += 25
            } else if !compactTerm.isEmpty, keywordsCompact.contains(compactTerm) {
                total += 20
            }
        }
        total += max(0, 20 - title.count / 4)
        return total
    }

    public static func ranked<T>(_ items: [T],
                                 query: String,
                                 fields: (T) -> (title: String, subtitle: String, keywords: String)) -> [T] {
        let terms = normalizedTerms(query)
        guard !terms.isEmpty else { return items }
        let ranked: [RankedItem<T>] = items.enumerated().compactMap { index, item in
            let values = fields(item)
            guard let score = score(title: values.title,
                                    subtitle: values.subtitle,
                                    keywords: values.keywords,
                                    query: query) else {
                return nil
            }
            return RankedItem(index: index, item: item, score: score)
        }
        return ranked.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.index < $1.index
        }
        .map(\.item)
    }

    public static func shortcutSearchKeywords(_ shortcutText: String?) -> String {
        guard let shortcutText = shortcutText?
            .trimmingCharacters(in: .whitespacesAndNewlines), !shortcutText.isEmpty else {
            return ""
        }

        let lower = shortcutText.lowercased()
        var tokens = [lower]
        let modifierTokens: [(symbol: Character, aliases: [String])] = [
            ("⌘", ["cmd", "command"]),
            ("⌥", ["option", "opt", "alt"]),
            ("⇧", ["shift"]),
            ("⌃", ["control", "ctrl"])
        ]
        let keyTokens: [(symbol: Character, aliases: [String])] = [
            ("↩", ["return", "enter"]),
            ("␣", ["space"]),
            ("⎋", ["escape", "esc"]),
            ("⌦", ["delete", "forwarddelete", "forward-delete"]),
            ("⌫", ["delete", "backspace"])
        ]

        for entry in modifierTokens + keyTokens where lower.contains(entry.symbol) {
            tokens.append(contentsOf: entry.aliases)
        }

        if lower.contains("esc") || lower.contains("escape") {
            tokens.append(contentsOf: ["escape", "esc"])
        }
        let key = lower
            .replacingOccurrences(of: "⌘", with: "")
            .replacingOccurrences(of: "⌥", with: "")
            .replacingOccurrences(of: "⇧", with: "")
            .replacingOccurrences(of: "⌃", with: "")
            .replacingOccurrences(of: "↩", with: "return")
            .replacingOccurrences(of: "␣", with: "space")
            .replacingOccurrences(of: "⎋", with: "esc")
            .replacingOccurrences(of: "⌦", with: "forwarddelete")
            .replacingOccurrences(of: "⌫", with: "backspace")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let keyAliases = shortcutKeyAliases(key)
        if !keyAliases.isEmpty {
            tokens.append(contentsOf: keyAliases)
        }

        let modifierAliasGroups = modifierTokens
            .filter { lower.contains($0.symbol) }
            .map(\.aliases)
        let modifierAliasCombinations = aliasCombinations(modifierAliasGroups)
        if !modifierAliasCombinations.isEmpty {
            for keyAlias in keyAliases {
                for modifierAliases in modifierAliasCombinations {
                    tokens.append((modifierAliases + [keyAlias]).joined())
                }
            }
        }

        return uniquePreservingOrder(tokens).joined(separator: " ")
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static func shortcutKeyAliases(_ key: String) -> [String] {
        guard !key.isEmpty else { return [] }
        switch key {
        case "space", "␣":
            return ["space"]
        case "return", "enter", "↩":
            return ["return", "enter"]
        case "esc", "escape", "⎋":
            return ["esc", "escape"]
        case "delete":
            return ["delete"]
        case "forwarddelete", "forward-delete", "⌦":
            return ["delete", "forwarddelete", "forward-delete"]
        case "backspace", "⌫":
            return ["delete", "backspace"]
        default:
            return [key]
        }
    }

    private static func aliasCombinations(_ groups: [[String]]) -> [[String]] {
        guard let first = groups.first else { return [] }
        return groups.dropFirst().reduce(first.map { [$0] }) { combinations, group in
            combinations.flatMap { combination in
                group.map { combination + [$0] }
            }
        }
    }

    private static func normalizedTerms(_ query: String) -> [String] {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: isQuerySeparator)
            .map(String.init)
    }

    private static func isQuerySeparator(_ character: Character) -> Bool {
        if character.isWhitespace { return true }
        return querySeparators.contains(character)
    }

    private static func compactSearchText(_ text: String) -> String {
        text
            .lowercased()
            .filter { !isQuerySeparator($0) }
    }
}
