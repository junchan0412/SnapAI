import Foundation

struct ResultRouteStatusText: Equatable {
    var primaryText: String
    var detailLines: [String]

    static func make(providerName: String,
                     modelName: String,
                     fallbackModelName: String,
                     contextSummary: String?,
                     routeExplanation: String?,
                     routeNote: String?) -> ResultRouteStatusText {
        ResultRouteStatusText(
            primaryText: primaryText(providerName: providerName,
                                     modelName: modelName,
                                     fallbackModelName: fallbackModelName),
            detailLines: detailLines(contextSummary: contextSummary,
                                     routeExplanation: routeExplanation,
                                     routeNote: routeNote)
        )
    }

    static func primaryText(providerName: String,
                            modelName: String,
                            fallbackModelName: String) -> String {
        let parts = [
            providerName.trimmingCharacters(in: .whitespacesAndNewlines),
            preferredModelName(modelName: modelName, fallbackModelName: fallbackModelName)
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? "正在准备请求" : parts.joined(separator: " / ")
    }

    static func detailLines(contextSummary: String?,
                            routeExplanation: String?,
                            routeNote: String?) -> [String] {
        var lines: [String] = []
        if let context = sanitized(contextSummary) {
            lines.append("上下文: \(context)")
        }
        if let explanation = sanitized(routeExplanation) {
            lines.append(explanation)
        }
        if let note = sanitized(routeNote) {
            lines.append(note)
        }
        return deduplicated(lines)
    }

    private static func preferredModelName(modelName: String,
                                           fallbackModelName: String) -> String {
        let active = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !active.isEmpty { return active }
        return fallbackModelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitized(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
