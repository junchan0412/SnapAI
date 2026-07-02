import Foundation

struct RoutePerformanceRecord: Codable, Equatable {
    var providerID: String
    var modelName: String
    var successCount: Int = 0
    var failureCount: Int = 0
    var firstTokenTotalMilliseconds: Int = 0
    var firstTokenSampleCount: Int = 0
    var elapsedTotalMilliseconds: Int = 0
    var elapsedSampleCount: Int = 0
    var failureReasons: [String: Int] = [:]
    var manualPreferenceScore: Int = 0
    var lastUpdated: Date = Date()

    var id: String { Self.id(providerID: providerID, modelName: modelName) }
    var attemptCount: Int { max(0, successCount) + max(0, failureCount) }
    var successRate: Double? {
        guard attemptCount > 0 else { return nil }
        return Double(max(0, successCount)) / Double(attemptCount)
    }
    var averageFirstTokenMilliseconds: Int? {
        guard firstTokenSampleCount > 0 else { return nil }
        return firstTokenTotalMilliseconds / firstTokenSampleCount
    }
    var averageElapsedMilliseconds: Int? {
        guard elapsedSampleCount > 0 else { return nil }
        return elapsedTotalMilliseconds / elapsedSampleCount
    }

    mutating func recordSuccess(elapsedMilliseconds: Int,
                                firstTokenMilliseconds: Int?) {
        successCount = min(successCount + 1, 100_000)
        recordElapsed(milliseconds: elapsedMilliseconds)
        recordFirstToken(milliseconds: firstTokenMilliseconds)
        lastUpdated = Date()
    }

    mutating func recordFailure(elapsedMilliseconds: Int,
                                firstTokenMilliseconds: Int?,
                                reason: String?) {
        failureCount = min(failureCount + 1, 100_000)
        recordElapsed(milliseconds: elapsedMilliseconds)
        recordFirstToken(milliseconds: firstTokenMilliseconds)
        let key = Self.failureReasonKey(reason)
        failureReasons[key, default: 0] = min(failureReasons[key, default: 0] + 1, 100_000)
        lastUpdated = Date()
    }

    mutating func recordManualPreference(delta: Int = 1) {
        manualPreferenceScore = min(max(manualPreferenceScore + delta, -10), 10)
        lastUpdated = Date()
    }

    func scoreAdjustment() -> Int {
        var value = 0
        if attemptCount >= 3, let successRate {
            value += Int(((successRate - 0.5) * 120.0).rounded())
        }
        if let averageFirstTokenMilliseconds {
            if averageFirstTokenMilliseconds <= 1_500 {
                value += 25
            } else if averageFirstTokenMilliseconds <= 4_000 {
                value += 10
            } else if averageFirstTokenMilliseconds >= 12_000 {
                value -= 30
            } else if averageFirstTokenMilliseconds >= 8_000 {
                value -= 15
            }
        }
        if let averageElapsedMilliseconds, averageElapsedMilliseconds >= 60_000 {
            value -= 15
        }
        value += min(max(manualPreferenceScore, -10), 10) * 12
        return min(max(value, -160), 160)
    }

    var performanceSummary: String {
        let rate = successRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        let firstToken = averageFirstTokenMilliseconds.map { "\($0)ms" } ?? "n/a"
        return "success=\(rate), firstToken=\(firstToken), attempts=\(attemptCount), preference=\(manualPreferenceScore)"
    }

    static func id(providerID: String, modelName: String) -> String {
        "\(providerID)::\(modelName)"
    }

    static func failureReasonKey(_ reason: String?) -> String {
        let sanitized = SensitiveTextSanitizer.sanitizedMessage(reason ?? "unknown", limit: 80)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "unknown" : sanitized
    }

    private mutating func recordElapsed(milliseconds: Int) {
        elapsedTotalMilliseconds = min(elapsedTotalMilliseconds + max(0, milliseconds), Int.max / 4)
        elapsedSampleCount = min(elapsedSampleCount + 1, 100_000)
    }

    private mutating func recordFirstToken(milliseconds: Int?) {
        guard let milliseconds else { return }
        firstTokenTotalMilliseconds = min(firstTokenTotalMilliseconds + max(0, milliseconds), Int.max / 4)
        firstTokenSampleCount = min(firstTokenSampleCount + 1, 100_000)
    }
}

struct RoutingMetricsTable: Codable, Equatable {
    var records: [String: RoutePerformanceRecord] = [:]

    static let empty = RoutingMetricsTable()

    mutating func recordSuccess(route: AIRequestRoute,
                                elapsedMilliseconds: Int,
                                firstTokenMilliseconds: Int?) {
        update(route: route) { record in
            record.recordSuccess(elapsedMilliseconds: elapsedMilliseconds,
                                 firstTokenMilliseconds: firstTokenMilliseconds)
        }
    }

    mutating func recordFailure(route: AIRequestRoute,
                                elapsedMilliseconds: Int,
                                firstTokenMilliseconds: Int?,
                                reason: String?) {
        update(route: route) { record in
            record.recordFailure(elapsedMilliseconds: elapsedMilliseconds,
                                 firstTokenMilliseconds: firstTokenMilliseconds,
                                 reason: reason)
        }
    }

    mutating func recordManualPreference(providerID: String,
                                         modelName: String,
                                         delta: Int = 1) {
        let id = RoutePerformanceRecord.id(providerID: providerID, modelName: modelName)
        var record = records[id] ?? RoutePerformanceRecord(providerID: providerID,
                                                           modelName: modelName)
        record.recordManualPreference(delta: delta)
        records[id] = record
    }

    func record(for route: AIRequestRoute) -> RoutePerformanceRecord? {
        records[route.id]
    }

    func scoreAdjustment(for route: AIRequestRoute) -> Int {
        record(for: route)?.scoreAdjustment() ?? 0
    }

    func preferredReason(providerID: String, modelName: String) -> String? {
        let id = RoutePerformanceRecord.id(providerID: providerID, modelName: modelName)
        guard let record = records[id],
              record.scoreAdjustment() >= 40 else {
            return nil
        }
        return "本机表现优先"
    }

    private mutating func update(route: AIRequestRoute,
                                 _ block: (inout RoutePerformanceRecord) -> Void) {
        var record = records[route.id] ?? RoutePerformanceRecord(providerID: route.providerID,
                                                                 modelName: route.modelName)
        block(&record)
        records[route.id] = record
        pruneIfNeeded()
    }

    private mutating func pruneIfNeeded(limit: Int = 500) {
        guard records.count > limit else { return }
        let keep = records.values
            .sorted { $0.lastUpdated > $1.lastUpdated }
            .prefix(limit)
        records = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
    }
}

final class RoutingMetricsStore {
    static let shared = RoutingMetricsStore()

    private let url: URL
    private let lock = NSLock()
    private var cached: RoutingMetricsTable?

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    func snapshot() -> RoutingMetricsTable {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let loaded = Self.load(from: url)
        cached = loaded
        return loaded
    }

    func recordSuccess(route: AIRequestRoute,
                       elapsedMilliseconds: Int,
                       firstTokenMilliseconds: Int?) {
        update { table in
            table.recordSuccess(route: route,
                                elapsedMilliseconds: elapsedMilliseconds,
                                firstTokenMilliseconds: firstTokenMilliseconds)
        }
    }

    func recordFailure(route: AIRequestRoute,
                       elapsedMilliseconds: Int,
                       firstTokenMilliseconds: Int?,
                       reason: String?) {
        update { table in
            table.recordFailure(route: route,
                                elapsedMilliseconds: elapsedMilliseconds,
                                firstTokenMilliseconds: firstTokenMilliseconds,
                                reason: reason)
        }
    }

    func recordManualPreference(providerID: String,
                                modelName: String) {
        update { table in
            table.recordManualPreference(providerID: providerID, modelName: modelName)
        }
    }

    private func update(_ block: (inout RoutingMetricsTable) -> Void) {
        lock.lock()
        var table = cached ?? Self.load(from: url)
        block(&table)
        cached = table
        let targetURL = url
        lock.unlock()
        Self.save(table, to: targetURL)
    }

    static func load(from url: URL) -> RoutingMetricsTable {
        guard let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(RoutingMetricsTable.self, from: data) else {
            return .empty
        }
        return table
    }

    static func save(_ table: RoutingMetricsTable, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(table)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("SnapAI: failed to save routing metrics: \(error.localizedDescription)")
        }
    }

    private static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SnapAI", isDirectory: true)
            .appendingPathComponent("routing-metrics.json")
    }
}
