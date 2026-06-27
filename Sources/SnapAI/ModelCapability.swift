import Foundation

struct ModelCapability: Equatable {
    var supportsVision: Bool
    var supportsReasoning: Bool
    var contextTokens: Int
    var isFast: Bool
    var isEconomical: Bool
    var isCodeCapable: Bool

    var supportsLongContext: Bool {
        contextTokens >= 100_000
    }
}

enum ModelCapabilityRegistry {
    static func capability(for modelName: String, providerName: String = "") -> ModelCapability {
        let model = modelName.lowercased()
        let provider = providerName.lowercased()
        let haystack = "\(provider) \(model)"

        let fast = containsAny(haystack, [
            "mini", "flash", "haiku", "lite", "turbo", "nano", "instant", "small", "chat"
        ])
        let economical = fast || containsAny(haystack, [
            "cheap", "economy", "low-cost"
        ])
        let reasoning = containsAny(haystack, [
            "reason", "reasoner", "thinking", "r1", "o1", "o3", "o4", "qwen3"
        ])
        let vision = containsAny(haystack, [
            "vision", "gpt-4o", "omni", "gemini", "claude", "sonnet", "opus", "haiku"
        ])
        let code = containsAny(haystack, [
            "code", "coder", "codestral", "deepseek", "qwen", "claude", "sonnet", "opus"
        ])

        return ModelCapability(
            supportsVision: vision,
            supportsReasoning: reasoning,
            contextTokens: inferredContextTokens(from: model),
            isFast: fast,
            isEconomical: economical,
            isCodeCapable: code
        )
    }

    private static func inferredContextTokens(from model: String) -> Int {
        if model.contains("2m") { return 2_000_000 }
        if model.contains("1m") { return 1_000_000 }
        if model.contains("200k") { return 200_000 }
        if model.contains("128k") { return 128_000 }
        if model.contains("100k") { return 100_000 }
        if model.contains("64k") { return 64_000 }
        if model.contains("32k") { return 32_000 }
        if model.contains("16k") { return 16_000 }
        if containsAny(model, ["claude", "sonnet", "opus"]) { return 200_000 }
        if model.contains("gemini") { return 1_000_000 }
        if model.contains("gpt-4o") || model.contains("o1") || model.contains("o3") || model.contains("o4") {
            return 128_000
        }
        return 8_000
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
