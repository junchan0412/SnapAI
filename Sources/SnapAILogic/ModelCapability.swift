import Foundation

package struct ModelMetadataOverrides: Codable, Equatable {
    package var supportsVision: Bool?
    package var supportsReasoning: Bool?
    package var contextTokens: Int?
    package var inputUSDPerMillionTokens: Double?
    package var outputUSDPerMillionTokens: Double?
    package var capabilitySource: String?
    package var pricingSource: String?

    package init(supportsVision: Bool? = nil,
                 supportsReasoning: Bool? = nil,
                 contextTokens: Int? = nil,
                 inputUSDPerMillionTokens: Double? = nil,
                 outputUSDPerMillionTokens: Double? = nil,
                 capabilitySource: String? = nil,
                 pricingSource: String? = nil) {
        self.supportsVision = supportsVision
        self.supportsReasoning = supportsReasoning
        self.contextTokens = contextTokens
        self.inputUSDPerMillionTokens = inputUSDPerMillionTokens
        self.outputUSDPerMillionTokens = outputUSDPerMillionTokens
        self.capabilitySource = capabilitySource
        self.pricingSource = pricingSource
    }

    package var sanitized: Self {
        var copy = self
        copy.contextTokens = contextTokens.flatMap { (1...100_000_000).contains($0) ? $0 : nil }
        copy.inputUSDPerMillionTokens = Self.validPrice(inputUSDPerMillionTokens)
        copy.outputUSDPerMillionTokens = Self.validPrice(outputUSDPerMillionTokens)
        copy.capabilitySource = Self.sourceText(capabilitySource)
        copy.pricingSource = Self.sourceText(pricingSource)
        return copy
    }

    package var hasCapabilityOverrides: Bool {
        supportsVision != nil || supportsReasoning != nil || contextTokens != nil
    }

    private static func validPrice(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...1_000_000).contains(value) else { return nil }
        return value
    }

    private static func sourceText(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_000))
        return text.isEmpty ? nil : text
    }
}

package struct ModelPricing: Equatable {
    package var inputUSDPerMillionTokens: Double
    package var outputUSDPerMillionTokens: Double
    package var source: String

    package func estimatedCost(inputTokens: Int, outputTokens: Int) -> Double {
        Double(max(0, inputTokens)) / 1_000_000 * inputUSDPerMillionTokens
            + Double(max(0, outputTokens)) / 1_000_000 * outputUSDPerMillionTokens
    }
}

package struct ModelCapability: Equatable {
    package var supportsVision: Bool
    package var supportsReasoning: Bool
    package var contextTokens: Int
    package var isFast: Bool
    package var isEconomical: Bool
    package var isCodeCapable: Bool

    package var supportsLongContext: Bool {
        contextTokens >= 100_000
    }
}

package enum ModelCapabilityRegistry {
    package static func capability(for modelName: String, provider: AIProvider) -> ModelCapability {
        var result = capability(for: modelName, providerName: provider.name)
        guard !provider.isAppleOnDevice,
              let metadata = provider.models.first(where: { $0.name == modelName })?.metadata.sanitized else {
            return result
        }
        if let value = metadata.supportsVision { result.supportsVision = value }
        if let value = metadata.supportsReasoning { result.supportsReasoning = value }
        if let value = metadata.contextTokens { result.contextTokens = value }
        return result
    }

    package static func pricing(providerID: String, modelName: String, settings: AppSettings) -> ModelPricing? {
        guard let provider = settings.providers.first(where: { $0.id == providerID }),
              let entry = provider.models.first(where: { $0.name == modelName }) else { return nil }
        if provider.isAppleOnDevice {
            return ModelPricing(inputUSDPerMillionTokens: 0, outputUSDPerMillionTokens: 0, source: "Apple 本机模型（无 API 费用）")
        }
        let metadata = entry.metadata.sanitized
        guard let input = metadata.inputUSDPerMillionTokens,
              let output = metadata.outputUSDPerMillionTokens else { return nil }
        return ModelPricing(inputUSDPerMillionTokens: input,
                            outputUSDPerMillionTokens: output,
                            source: metadata.pricingSource ?? "手工配置（未填写来源）")
    }

    package static func capability(for modelName: String, providerName: String = "") -> ModelCapability {
        // Apple 端侧模型:画像固定(无视觉/短上下文/快速省钱),不走启发式猜测。
        if providerName == AppleOnDeviceModel.providerName
            || modelName == AppleOnDeviceModel.modelName {
            return AppleOnDeviceModel.capability()
        }
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
