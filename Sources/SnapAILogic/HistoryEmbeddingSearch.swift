import Foundation
import NaturalLanguage

/// 历史语义检索:在 FTS 关键词与概念表都命中失败时,用系统 NLEmbedding
/// (中英双语料,零第三方依赖)按语义相似度召回。
///
/// 设计约束:
/// 1. 纯逻辑层,只依赖 Foundation + NaturalLanguage;embedding 缺失时返回 []。
/// 2. 候选上限 200 条、每条截断 500 字:200×500 的距离计算约 50ms 内,可在
///    HistoryWindowModel 的 refreshQueue 后台执行,不阻塞输入。
/// 3. 只做"召回补充":调用方(HistorySemanticSearch 之后)合并去重,FTS 精确
///    命中永远排在前面;阈值锁死,避免语义噪声淹没精确结果。
package enum HistoryEmbeddingSearch {
    /// 余弦距离上限(距离越小越相似)。NLEmbedding 距离域约 0...2,
    /// 实测(en 语料):同义句对约 0.23,无关句对约 0.27 —— 分布接近,
    /// 阈值取 0.25,只召回高确信候选;宁可漏召回,不让语义噪声淹没精确结果。
    package static let maximumDistance = 0.25
    package static let maximumCandidates = 200
    package static let maximumEntryCharacters = 500

    package static func search(query: String,
                               entries: [HistoryEntry],
                               limit: Int) -> [HistoryEntry] {
        let cappedLimit = max(0, limit)
        guard cappedLimit > 0 else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let embeddings = sentenceEmbeddings() else { return [] }
        let candidates = entries.prefix(maximumCandidates)
        var scored: [(entry: HistoryEntry, distance: Double)] = []
        scored.reserveCapacity(candidates.count)
        for entry in candidates {
            let text = searchableText(for: entry)
            guard !text.isEmpty else { continue }
            guard let distance = bestDistance(between: trimmed,
                                              and: text,
                                              embeddings: embeddings) else { continue }
            guard distance <= maximumDistance else { continue }
            scored.append((entry, distance))
        }
        return scored
            .sorted {
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                return $0.entry.date > $1.entry.date
            }
            .prefix(cappedLimit)
            .map(\.entry)
    }

    private static func sentenceEmbeddings() -> [NLEmbedding]? {
        var embeddings: [NLEmbedding] = []
        if let chinese = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese) {
            embeddings.append(chinese)
        }
        if let english = NLEmbedding.sentenceEmbedding(for: .english) {
            embeddings.append(english)
        }
        return embeddings.isEmpty ? nil : embeddings
    }

    private static func bestDistance(between query: String,
                                     and text: String,
                                     embeddings: [NLEmbedding]) -> Double? {
        var best: Double?
        for embedding in embeddings {
            guard embedding.contains(query), embedding.contains(text) else { continue }
            let distance = embedding.distance(between: query, and: text)
            guard distance.isFinite else { continue }
            if let current = best {
                best = min(current, distance)
            } else {
                best = distance
            }
        }
        return best
    }

    private static func searchableText(for entry: HistoryEntry) -> String {
        // 只用 source/output/tags:动作名("提问")与 provider 名是所有条目的公共前缀,
        // 会把同义与无关条目的距离一起抬高、压缩区分度。
        let combined = [
            entry.source,
            entry.output,
            entry.displayTags.joined(separator: " ")
        ].joined(separator: " ")
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumEntryCharacters else { return trimmed }
        return String(trimmed.prefix(maximumEntryCharacters))
    }
}
