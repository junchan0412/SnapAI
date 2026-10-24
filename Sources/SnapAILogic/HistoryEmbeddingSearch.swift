import Foundation
import NaturalLanguage

/// 历史语义检索:在 FTS 关键词与概念匹配后,用系统 NLEmbedding 补充召回
/// (中英双语料,零第三方依赖)按语义相似度召回。
///
/// 设计约束:
/// 1. 纯逻辑层,只依赖 Foundation + NaturalLanguage;embedding 缺失时返回 []。
/// 2. 候选上限 200 条、每条截断 500 字,在 HistoryWindowModel 的后台队列执行。
///    系统距离仅做有界内存缓存,每次查询仍只从当前历史条目中召回。
/// 3. 只做"召回补充":调用方(HistorySemanticSearch 之后)合并去重,FTS 精确
///    命中永远排在前面;阈值锁死,避免语义噪声淹没精确结果。
package enum HistoryEmbeddingSearch {
    /// 系统距离上限(距离越小越相似)。NLEmbedding 距离域约 0...2,
    /// 实测(en 语料):同义句对约 0.23,无关句对约 0.27 —— 分布接近,
    /// 阈值取 0.25,只召回高确信候选;宁可漏召回,不让语义噪声淹没精确结果。
    package static let maximumDistance = 0.25
    package static let maximumCandidates = 200
    package static let maximumEntryCharacters = 500
    private static let distanceCache = DistanceCache()

    package struct DistanceKey: Hashable {
        package var language: String
        package var revision: Int
        package var query: String
        package var text: String
    }

    package final class DistanceCache: @unchecked Sendable {
        private struct Value {
            var distance: Double?
        }
        private let lock = NSLock()
        private let capacity: Int
        private var values: [DistanceKey: Value] = [:]
        private var order: [DistanceKey] = []

        package init(capacity: Int = 512) {
            self.capacity = max(1, capacity)
        }

        package func distance(for key: DistanceKey, compute: () -> Double?) -> Double? {
            lock.lock()
            if let cached = values[key] {
                lock.unlock()
                return cached.distance
            }
            lock.unlock()
            let distance = compute()
            lock.lock()
            defer { lock.unlock() }
            if let cached = values[key] { return cached.distance }
            if order.count >= capacity {
                values.removeValue(forKey: order.removeFirst())
            }
            order.append(key)
            values[key] = Value(distance: distance)
            return distance
        }
    }

    package static func search(query: String,
                               entries: [HistoryEntry],
                               limit: Int,
                               shouldCancel: () -> Bool = { false },
                               distanceFunctions: [(String, String) -> Double?]? = nil) -> [HistoryEntry] {
        let cappedLimit = max(0, limit)
        guard !shouldCancel(), cappedLimit > 0 else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let distances = distanceFunctions ?? sentenceDistances(shouldCancel: shouldCancel)
        guard !shouldCancel(), !distances.isEmpty else { return [] }
        let candidates = entries.prefix(maximumCandidates)
        var scored: [(entry: HistoryEntry, distance: Double)] = []
        scored.reserveCapacity(candidates.count)
        for entry in candidates {
            guard !shouldCancel() else { return [] }
            let text = searchableText(for: entry)
            guard !text.isEmpty else { continue }
            guard let distance = bestDistance(between: trimmed,
                                              and: text,
                                              distances: distances,
                                              shouldCancel: shouldCancel) else { continue }
            guard distance <= maximumDistance else { continue }
            scored.append((entry, distance))
        }
        guard !shouldCancel() else { return [] }
        return scored
            .sorted {
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                return $0.entry.date > $1.entry.date
            }
            .prefix(cappedLimit)
            .map(\.entry)
    }

    private static func sentenceDistances(shouldCancel: () -> Bool) -> [(String, String) -> Double?] {
        var distances: [(String, String) -> Double?] = []
        for language in [NLLanguage.simplifiedChinese, .english] {
            guard !shouldCancel() else { return [] }
            guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else { continue }
            distances.append { query, text in
                let key = DistanceKey(language: language.rawValue,
                                      revision: embedding.revision,
                                      query: query,
                                      text: text)
                return distanceCache.distance(for: key) {
                    guard embedding.contains(query), embedding.contains(text) else { return nil }
                    let distance = embedding.distance(between: query, and: text)
                    return distance.isFinite ? distance : nil
                }
            }
        }
        return distances
    }

    private static func bestDistance(between query: String,
                                     and text: String,
                                     distances: [(String, String) -> Double?],
                                     shouldCancel: () -> Bool) -> Double? {
        var best: Double?
        for distanceFunction in distances {
            guard !shouldCancel() else { return nil }
            guard let distance = distanceFunction(query, text) else { continue }
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
