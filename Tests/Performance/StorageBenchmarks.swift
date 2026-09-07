import Foundation

@main struct HistoryStoreBenchmark {
    static func main() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SnapAI-RealStorageBench-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        let source = String(String(repeating: "synthetic text benchmark storage. ", count: 80).prefix(2_000))
        let output = String(String(repeating: "stream output persistence schema. ", count: 80).prefix(2_000))
        let entries = (0..<500).map { index in
            HistoryEntry(id: "record-\(index)", date: Date(timeIntervalSince1970: Double(index)),
                         actionName: "总结", source: source, output: output,
                         provider: "Test", model: "synthetic-model", tags: ["fixture"])
        }
        let clock = ContinuousClock()
        let populate = clock.measure { precondition(store.replaceAll(entries, limit: 500)) }
        let reads = clock.measure { for _ in 0..<30 { precondition(store.load(limit: 500).count == 500) } }
        let favorites = clock.measure {
            for index in 0..<50 {
                var updated = entries[index]
                updated.isFavorite = true
                precondition(store.upsert(updated, limit: 500))
            }
        }
        func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        }
        let values = ["populate_ms": milliseconds(populate),
                      "30_full_reads_ms": milliseconds(reads),
                      "50_favorite_updates_ms": milliseconds(favorites)]
        let data = try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
