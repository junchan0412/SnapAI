import Foundation

/// 用量看板聚合:从 RoutingMetricsTable 计算各供应商请求数/成功率/平均耗时。
///
/// 设计约束:
/// 1. 纯值语义、可测试,不碰文件与网络;输入 RoutingMetricsTable,输出展示行。
/// 2. 无 token 计数器(请求层不记录 token),估算列用 elapsed 派生,不虚构精确 token 数。
/// 3. 空数据返回空数组,调用方显示"暂无数据"占位,不展示 0 行表格。
package struct UsageDashboard {
    package struct ProviderRow: Equatable {
        package var providerID: String
        package var displayName: String
        package var requests: Int
        package var successRate: Double?
        package var averageElapsedMilliseconds: Int?
        package var lastActive: Date?

        package var successRateText: String {
            guard let successRate else { return "—" }
            return "\(Int((successRate * 100).rounded()))%"
        }

        package var averageElapsedText: String {
            guard let ms = averageElapsedMilliseconds else { return "—" }
            if ms < 1_000 { return "\(ms)ms" }
            return String(format: "%.1fs", Double(ms) / 1_000)
        }
    }

    /// 按供应商聚合,按请求数降序。providerNames 用于把 id 还原为展示名。
    package static func rows(table: RoutingMetricsTable,
                             providerNames: [String: String] = [:]) -> [ProviderRow] {
        var grouped: [String: (requests: Int, success: Int, elapsed: Int, elapsedSamples: Int, last: Date?)] = [:]
        for record in table.records.values {
            var entry = grouped[record.providerID] ?? (0, 0, 0, 0, nil)
            entry.requests += record.attemptCount
            entry.success += max(0, record.successCount)
            entry.elapsed += max(0, record.elapsedTotalMilliseconds)
            entry.elapsedSamples += max(0, record.elapsedSampleCount)
            if let last = entry.last {
                entry.last = max(last, record.lastUpdated)
            } else {
                entry.last = record.lastUpdated
            }
            grouped[record.providerID] = entry
        }
        return grouped
            .filter { $0.value.requests > 0 }
            .map { providerID, entry in
                ProviderRow(
                    providerID: providerID,
                    displayName: providerNames[providerID] ?? providerID,
                    requests: entry.requests,
                    successRate: entry.requests > 0 ? Double(entry.success) / Double(entry.requests) : nil,
                    averageElapsedMilliseconds: entry.elapsedSamples > 0 ? entry.elapsed / entry.elapsedSamples : nil,
                    lastActive: entry.last
                )
            }
            .sorted { $0.requests > $1.requests }
    }

    package static func totalRequests(rows: [ProviderRow]) -> Int {
        rows.reduce(0) { $0 + $1.requests }
    }
}
