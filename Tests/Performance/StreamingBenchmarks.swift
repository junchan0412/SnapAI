import Foundation

@main
struct StreamingBenchmarks {
    static func main() {
        let plainDocument = (0..<400).map {
            "这是用于离线性能验证的普通段落，保留中文和 emoji 🌏，段落序号 \($0)。"
        }.joined(separator: "\n\n")
        let mixedDocument = (0..<200).map {
            "## 标题 \($0)\n\n正文 **重点** 和 [链接](https://example.com)\n\n- 第一项\n- 第二项"
        }.joined(separator: "\n\n")
        let thinkingDocument = String(repeating: "答<think>思考</think>", count: 6_000)

        measure("markdown_plain_400_paragraphs", iterations: 15) {
            MarkdownPresentationBuilder.build(plainDocument).blocks.count
        }
        measure("markdown_mixed_200_sections", iterations: 15) {
            MarkdownPresentationBuilder.build(mixedDocument).blocks.count
        }
        measure("thinking_6000_spans_single_chunk", iterations: 7) {
            var accumulator = StreamingAccumulator()
            _ = accumulator.appendContentToken(thinkingDocument, extractsThinkTags: true)
            return accumulator.outputText.utf8.count + accumulator.thinkingText.utf8.count
        }
    }

    private static func measure(_ name: String, iterations: Int, operation: () -> Int) {
        var samples: [Double] = []
        var checksum = 0
        for _ in 0..<iterations {
            let started = ProcessInfo.processInfo.systemUptime
            checksum += operation()
            samples.append((ProcessInfo.processInfo.systemUptime - started) * 1_000)
        }
        samples.sort()
        let median = String(format: "%.3f", samples[samples.count / 2])
        print("\(name): median_ms=\(median) checksum=\(checksum) iterations=\(iterations)")
    }
}
