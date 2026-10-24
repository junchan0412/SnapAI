import Foundation
import SnapAILogic

@main struct Probe {
    @MainActor static func main() async throws {
        guard let raw = UserDefaults(suiteName: "com.snapai.app")?.data(forKey: "SnapAI.settings.v1") else { return }
        let original = try JSONDecoder().decode(AppSettings.self, from: raw)
        let indices = [2, 0, 1]
        var results: [[String: Any]] = []
        for index in indices where original.providers.indices.contains(index) {
            var provider = original.providers[index]
            guard let model = provider.models.first(where: { $0.enabled })?.name else { continue }
            provider.apiKey = LocalSecretStore.apiKey(for: provider.id)
            guard !provider.apiKey.isEmpty else { continue }
            provider.maxTokens = 32
            provider.requestTimeout = 20
            let settings = AppSettings()
            settings.providers = [provider]
            settings.activeProviderID = provider.id
            settings.activeModel = model
            let client = AIClient(settings: settings)
            var output = ""
            let start = Date()
            var first: Date?
            let error: Error? = await withCheckedContinuation { continuation in
                client.stream(messages: [ChatMessage(role: .user, content: "Reply with exactly: SNAPAI-ACCEPTANCE-OK")], action: nil,
                    onToken: { token in if first == nil { first = Date() }; output += token },
                    onComplete: { continuation.resume(returning: $0) })
            }
            var result: [String: Any] = ["provider_index": index, "model": model,
                "status": error == nil ? "success" : "failed", "elapsed_ms": Int(Date().timeIntervalSince(start) * 1000),
                "output": output, "ttft_ms": first.map { Int($0.timeIntervalSince(start) * 1000) } ?? -1]
            if let error { result["error"] = SensitiveTextSanitizer.sanitizedMessage(error.localizedDescription, limit: 300) }
            if let usage = client.latestUsage { result["usage"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(usage)) }
            results.append(result)
            let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            print("Provider \(index) \(model): \(result["status"]!)")
            if error == nil && output.contains("SNAPAI-ACCEPTANCE-OK") { break }
        }
    }
}
