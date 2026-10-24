import Foundation
import SnapAILogic

@main struct Probe {
    @MainActor static func main() async throws {
        guard let raw = UserDefaults(suiteName: "com.snapai.app")?.data(forKey: "SnapAI.settings.v1") else { return }
        let original = try JSONDecoder().decode(AppSettings.self, from: raw)
        let inputs = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String: String]]
        let indices = Array(repeating: 0, count: inputs.count)
        var requestNumber = 0
        var tokensUsed = 0
        var results: [[String: Any]] = []
        for index in indices where original.providers.indices.contains(index) {
            var provider = original.providers[index]
            guard let model = provider.models.first(where: { $0.enabled && $0.name == "deepseek-v4" })?.name else { continue }
            provider.apiKey = LocalSecretStore.apiKey(for: provider.id)
            guard !provider.apiKey.isEmpty else { continue }
            provider.maxTokens = 1600
            provider.requestTimeout = 40
            let settings = AppSettings()
            settings.providers = [provider]
            settings.activeProviderID = provider.id
            settings.activeModel = model
            let task = inputs[requestNumber % inputs.count]
            let round = requestNumber / inputs.count + 1
            requestNumber += 1
            let reserve = task["prompt"]!.utf8.count + 1000
            if tokensUsed + reserve > 22000 { break }
            let client = AIClient(settings: settings)
            var output = ""
            let start = Date()
            var first: Date?
            let error: Error? = await withCheckedContinuation { continuation in
                client.stream(messages: [ChatMessage(role: .user, content: task["prompt"]!)], action: nil,
                    onToken: { token in if first == nil { first = Date() }; output += token },
                    onComplete: { continuation.resume(returning: $0) })
            }
            var result: [String: Any] = ["task": task["id"]!, "round": round, "anonymous_id": "B\(String(format: "%03d", requestNumber))", "provider_index": index, "model": model,
                "status": error == nil ? "success" : "failed", "elapsed_ms": Int(Date().timeIntervalSince(start) * 1000),
                "output": output, "ttft_ms": first.map { Int($0.timeIntervalSince(start) * 1000) } ?? -1]
            if let error { result["error"] = SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription, limit: 300) }
            if let usage = client.latestUsage {
                result["usage"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(usage))
                tokensUsed += (usage.inputTokens ?? task["prompt"]!.utf8.count) + (usage.outputTokens ?? 1000)
            } else { tokensUsed += reserve }
            result["cumulative_tokens"] = tokensUsed
            results.append(result)
            let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            print("Provider \(index) \(model): \(result["status"]!)")
            if error != nil { break }
        }
    }
}
