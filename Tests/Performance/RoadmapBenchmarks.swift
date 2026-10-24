import Foundation
import NaturalLanguage

@main
struct RoadmapBenchmarks {
    private static let iterations = min(100, max(1, Int(ProcessInfo.processInfo.environment["SNAPAI_BENCHMARK_SAMPLES"] ?? "30") ?? 30))

    static func main() throws {
        var measurements: [[String: Any]] = []
        let section = """
        ## 长文阅读 Long answer

        正文保留中文、English、emoji 🌏，包含 **重点** 和 [链接](https://example.com)。

        7. 第一步
           - [x] 保留层级
        8. 第二步

        | 功能 | 状态 | 数量 |
        | :--- | :---: | ---: |
        | 表格 | 可读 | 3 |
        | 代码 | 可复制 | 42 |

        ```swift
        let message = "中文 answer" // highlight and preserve source
        if message.isEmpty { print(42) }
        ```


        """
        for size in [10_000, 40_000, 100_000] {
            let text = String(String(repeating: section, count: size / section.count + 1).prefix(size))
            let expectedBlocks = MarkdownPresentationBuilder.build(text).blocks.count
            var row = measure(name: "markdown_mixed", operation: {
                let result = MarkdownPresentationBuilder.build(text)
                precondition(result.blocks.count == expectedBlocks)
                return result.blocks.count
            })
            row["characters"] = text.count
            row["utf8_bytes"] = text.utf8.count
            row["cache"] = "warm parser; one untimed build before samples"
            measurements.append(row)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapAI-RoadmapBench-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let embeddingAvailability = [
            "english": NLEmbedding.sentenceEmbedding(for: .english) != nil,
            "simplified_chinese": NLEmbedding.sentenceEmbedding(for: .simplifiedChinese) != nil
        ]
        for count in [50, 200, 500] {
            let url = directory.appendingPathComponent("history-\(count).sqlite")
            let source = String(String(repeating: "synthetic source benchmark storage. ", count: 80).prefix(2_000))
            let output = String(String(repeating: "synthetic result stream persistence. ", count: 80).prefix(2_000))
            let entries = (0..<count).map { index in
                HistoryEntry(id: "record-\(index)", date: Date(timeIntervalSince1970: Double(index)),
                             actionName: "总结", source: source,
                             output: output + (index.isMultiple(of: 10) ? " needle" : " other"),
                             provider: "Test", model: "synthetic-model", tags: ["fixture"])
            }
            precondition(HistoryStore(url: url).replaceAll(entries, limit: count))
            let warmStore = HistoryStore(url: url)
            precondition(warmStore.load(limit: count).count == count)
            precondition(warmStore.search("needle", limit: count).count == count / 10)
            let criteria = HistoryFilterCriteria(query: "needle")
            let requiredIDs = Set(entries.filter { $0.output.hasSuffix(" needle") }.map(\.id))
            _ = HistorySearch.filteredEntries(criteria: criteria, memoryEntries: entries,
                                               limit: count, searchStore: warmStore.search)
            for query in ["load", "fts_search", "full_search"] {
                for cache in ["cold_connection", "warm_connection"] {
                    var row = measure(name: "history_\(query)", operation: {
                        let store = cache == "warm_connection" ? warmStore : HistoryStore(url: url)
                        let found: [HistoryEntry]
                        switch query {
                        case "load": found = store.load(limit: count)
                        case "fts_search": found = store.search("needle", limit: count)
                        default:
                            found = HistorySearch.filteredEntries(criteria: criteria, memoryEntries: entries,
                                                                  limit: count, searchStore: store.search)
                        }
                        if query == "full_search" {
                            precondition(requiredIDs.isSubset(of: Set(found.map(\.id))) && found.count <= count)
                        } else {
                            precondition(found.count == (query == "load" ? count : count / 10))
                        }
                        return found.count
                    })
                    row["rows"] = count
                    row["cache"] = cache
                    row["query"] = query == "load" ? "ORDER BY date DESC LIMIT row_count" : "needle"
                    row["minimum_expected_results"] = query == "load" ? count : count / 10
                    measurements.append(row)
                }
            }
        }
        let result: [String: Any] = [
            "schema_version": 1,
            "percentiles": "nearest rank: sorted[ceil(p * count) - 1]",
            "clock": "ProcessInfo.systemUptime; milliseconds",
            "history_fixture": "synthetic 2000-character source and 2000-character output plus one search term; 10% FTS matches",
            "cold_definition": "new HistoryStore/SQLite connection for each sample; existing populated database; OS file cache is not flushed",
            "warm_definition": "one reused SQLite connection after untimed load and search",
            "full_search_definition": "HistorySearch.filteredEntries: FTS, in-memory matching, concepts and available system NLEmbedding; memory entries are already loaded",
            "system_sentence_embeddings_available": embeddingAvailability,
            "scope": "logic microbenchmarks; excludes SwiftUI layout, display frame time, main-thread stalls, RSS, debounce and presentation publication",
            "measurements": measurements
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func measure(name: String, operation: () -> Int) -> [String: Any] {
        var samples: [Double] = []
        var checksum = 0
        for _ in 0..<iterations {
            autoreleasepool {
                let started = ProcessInfo.processInfo.systemUptime
                checksum += operation()
                samples.append((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            }
        }
        let sorted = samples.sorted()
        return ["name": name, "iterations": iterations, "samples_ms": samples, "checksum": checksum,
                "p50_ms": sorted[Int(ceil(Double(iterations) * 0.50)) - 1],
                "p95_ms": sorted[Int(ceil(Double(iterations) * 0.95)) - 1],
                "minimum_ms": sorted.first!, "maximum_ms": sorted.last!]
    }
}
