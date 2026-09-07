import Foundation

package struct RoutePerformanceRecord: Codable, Equatable {
    package var providerID: String
    package var modelName: String
    package var successCount: Int = 0
    package var failureCount: Int = 0
    package var firstTokenTotalMilliseconds: Int = 0
    package var firstTokenSampleCount: Int = 0
    package var elapsedTotalMilliseconds: Int = 0
    package var elapsedSampleCount: Int = 0
    package var failureReasons: [String: Int] = [:]
    package var manualPreferenceScore: Int = 0
    package var lastUpdated: Date = Date()

    package var id: String { Self.id(providerID: providerID, modelName: modelName) }
    package var attemptCount: Int { max(0, successCount) + max(0, failureCount) }
    package var successRate: Double? {
        guard attemptCount > 0 else { return nil }
        return Double(max(0, successCount)) / Double(attemptCount)
    }
    package var averageFirstTokenMilliseconds: Int? {
        guard firstTokenSampleCount > 0 else { return nil }
        return firstTokenTotalMilliseconds / firstTokenSampleCount
    }
    package var averageElapsedMilliseconds: Int? {
        guard elapsedSampleCount > 0 else { return nil }
        return elapsedTotalMilliseconds / elapsedSampleCount
    }

    package mutating func recordSuccess(elapsedMilliseconds: Int,
                                firstTokenMilliseconds: Int?) {
        successCount = min(successCount + 1, 100_000)
        recordElapsed(milliseconds: elapsedMilliseconds)
        recordFirstToken(milliseconds: firstTokenMilliseconds)
        lastUpdated = Date()
    }

    package mutating func recordFailure(elapsedMilliseconds: Int,
                                firstTokenMilliseconds: Int?,
                                reason: String?) {
        failureCount = min(failureCount + 1, 100_000)
        recordElapsed(milliseconds: elapsedMilliseconds)
        recordFirstToken(milliseconds: firstTokenMilliseconds)
        let key = Self.failureReasonKey(reason)
        failureReasons[key, default: 0] = min(failureReasons[key, default: 0] + 1, 100_000)
        lastUpdated = Date()
    }

    package mutating func recordManualPreference(delta: Int = 1) {
        manualPreferenceScore = min(max(manualPreferenceScore + delta, -10), 10)
        lastUpdated = Date()
    }

    package func scoreAdjustment() -> Int {
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

    package var performanceSummary: String {
        let rate = successRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        let firstToken = averageFirstTokenMilliseconds.map { "\($0)ms" } ?? "n/a"
        return "success=\(rate), firstToken=\(firstToken), attempts=\(attemptCount), preference=\(manualPreferenceScore)"
    }

    package static func id(providerID: String, modelName: String) -> String {
        "\(providerID)::\(modelName)"
    }

    package static func failureReasonKey(_ reason: String?) -> String {
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

package struct RoutingMetricsTable: Codable, Equatable {
    package var records: [String: RoutePerformanceRecord] = [:]

    package static let empty = RoutingMetricsTable()

    package mutating func recordSuccess(route: AIRequestRoute,
                                elapsedMilliseconds: Int,
                                firstTokenMilliseconds: Int?) {
        update(route: route) { record in
            record.recordSuccess(elapsedMilliseconds: elapsedMilliseconds,
                                 firstTokenMilliseconds: firstTokenMilliseconds)
        }
    }

    package mutating func recordFailure(route: AIRequestRoute,
                                elapsedMilliseconds: Int,
                                firstTokenMilliseconds: Int?,
                                reason: String?) {
        update(route: route) { record in
            record.recordFailure(elapsedMilliseconds: elapsedMilliseconds,
                                 firstTokenMilliseconds: firstTokenMilliseconds,
                                 reason: reason)
        }
    }

    package mutating func recordManualPreference(providerID: String,
                                         modelName: String,
                                         delta: Int = 1) {
        let id = RoutePerformanceRecord.id(providerID: providerID, modelName: modelName)
        var record = records[id] ?? RoutePerformanceRecord(providerID: providerID,
                                                           modelName: modelName)
        record.recordManualPreference(delta: delta)
        records[id] = record
    }

    package func record(for route: AIRequestRoute) -> RoutePerformanceRecord? {
        records[route.id]
    }

    package func scoreAdjustment(for route: AIRequestRoute) -> Int {
        record(for: route)?.scoreAdjustment() ?? 0
    }

    package func preferredReason(providerID: String, modelName: String) -> String? {
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

package final class RoutingMetricsStore {
    package static let shared = RoutingMetricsStore()

    private let url: URL
    private let lock = NSLock()
    private let persistenceQueue: DispatchQueue
    private let saveDelay: TimeInterval
    private let saveHandler: (RoutingMetricsTable, URL) -> Void
    private var cached: RoutingMetricsTable?
    private var persistenceGeneration = 0

    package init(url: URL? = nil,
         saveDelay: TimeInterval = 0.35,
         persistenceQueue: DispatchQueue? = nil,
         saveHandler: ((RoutingMetricsTable, URL) -> Void)? = nil) {
        self.url = url ?? Self.defaultURL()
        self.saveDelay = max(0, saveDelay)
        self.persistenceQueue = persistenceQueue
            ?? DispatchQueue(label: "com.snapai.routing-metrics-persistence", qos: .utility)
        self.saveHandler = saveHandler ?? Self.save
    }

    package func snapshot() -> RoutingMetricsTable {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let loaded = Self.load(from: url)
        cached = loaded
        return loaded
    }

    package func recordSuccess(route: AIRequestRoute,
                       elapsedMilliseconds: Int,
                       firstTokenMilliseconds: Int?) {
        update { table in
            table.recordSuccess(route: route,
                                elapsedMilliseconds: elapsedMilliseconds,
                                firstTokenMilliseconds: firstTokenMilliseconds)
        }
    }

    package func recordFailure(route: AIRequestRoute,
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

    package func recordManualPreference(providerID: String,
                                modelName: String) {
        update { table in
            table.recordManualPreference(providerID: providerID, modelName: modelName)
        }
    }

    package func flushPersistence() {
        let snapshot: RoutingMetricsTable
        let targetURL: URL
        lock.lock()
        persistenceGeneration += 1
        snapshot = cached ?? Self.load(from: url)
        targetURL = url
        lock.unlock()

        persistenceQueue.sync {
            saveHandler(snapshot, targetURL)
        }
    }

    private func update(_ block: (inout RoutingMetricsTable) -> Void) {
        lock.lock()
        var table = cached ?? Self.load(from: url)
        block(&table)
        cached = table
        let targetURL = url
        persistenceGeneration += 1
        let generation = persistenceGeneration
        lock.unlock()

        persistenceQueue.asyncAfter(deadline: .now() + saveDelay) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let isLatest = self.persistenceGeneration == generation
            self.lock.unlock()
            guard isLatest else { return }
            self.saveHandler(table, targetURL)
        }
    }

    package static func load(from url: URL) -> RoutingMetricsTable {
        guard let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(RoutingMetricsTable.self, from: data) else {
            return .empty
        }
        return table
    }

    package static func save(_ table: RoutingMetricsTable, to url: URL) {
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
        if ProcessInfo.processInfo.environment["SNAPAI_LOGIC_TESTS"] == "1" {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("SnapAI-LogicTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
                .appendingPathComponent("routing-metrics.json")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SnapAI", isDirectory: true)
            .appendingPathComponent("routing-metrics.json")
    }
}
