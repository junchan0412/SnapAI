import Foundation
import CoreFoundation

package struct AIUsage: Codable, Equatable, Sendable {
    package var inputTokens: Int?
    package var outputTokens: Int?
    package var cachedInputTokens: Int?
    package var cacheCreationInputTokens: Int?
    package var isFinal = true

    package var isComplete: Bool { isFinal && inputTokens != nil && outputTokens != nil }

    package mutating func merge(_ other: AIUsage) {
        inputTokens = other.inputTokens ?? inputTokens
        if other.outputTokens != nil { isFinal = other.isFinal }
        outputTokens = other.outputTokens ?? outputTokens
        cachedInputTokens = other.cachedInputTokens ?? cachedInputTokens
        cacheCreationInputTokens = other.cacheCreationInputTokens ?? cacheCreationInputTokens
    }

    package static func parse(_ json: [String: Any], apiProtocol: APIProtocol) -> AIUsage? {
        func count(_ value: Any?) -> Int? {
            guard let value = value as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite,
                  value.doubleValue >= 0, value.doubleValue <= 1_000_000_000,
                  value.doubleValue.rounded(.down) == value.doubleValue else { return nil }
            return value.intValue
        }
        let usage: AIUsage
        switch apiProtocol {
        case .openAI:
            usage = AIUsage(inputTokens: count(json["prompt_tokens"]),
                            outputTokens: count(json["completion_tokens"]),
                            cachedInputTokens: count((json["prompt_tokens_details"] as? [String: Any])?["cached_tokens"]))
        case .anthropic:
            let input = count(json["input_tokens"])
            let cached = count(json["cache_read_input_tokens"])
            let created = count(json["cache_creation_input_tokens"])
            usage = AIUsage(inputTokens: input.map { $0 + (cached ?? 0) + (created ?? 0) },
                            outputTokens: count(json["output_tokens"]),
                            cachedInputTokens: cached, cacheCreationInputTokens: created)
        }
        return usage.inputTokens == nil && usage.outputTokens == nil ? nil : usage
    }
}
