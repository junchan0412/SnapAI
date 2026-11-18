import SwiftUI
import SnapAILogic

struct RequestUsageDashboardView: View {
    @ObservedObject var settings: AppSettings
    @State private var table = RoutingMetricsStore.shared.snapshot()
    @State private var budget = ""
    @State private var budgetError: String?
    @State private var showDetails = false

    private var month: [RequestUsageDay] { UsageDashboard.currentMonth(table: table) }

    var body: some View {
        let names = Dictionary(uniqueKeysWithValues: settings.providers.map { ($0.id, $0.name) })
        let rows = UsageDashboard.rows(table: table, providerNames: names)
        let requests = month.reduce(0) { $0 + $1.requests }
        let inputTok = month.reduce(0) { $0 + $1.inputTokens }
        let outputTok = month.reduce(0) { $0 + $1.outputTokens }
        let firstSamples = month.reduce(0) { $0 + $1.firstTokenSamples }
        let avgTTFT = firstSamples > 0
            ? "\(month.reduce(0) { $0 + $1.firstTokenTotalMilliseconds } / firstSamples) ms"
            : "—"
        let cost = month.reduce(0) { $0 + $1.estimatedUSD }

        SnapAISectionGroup("本月用量与预算", subtitle: "统计 API 返回的 Token 与手工单价估算花费") {
            Button {
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(SnapAIIconButtonStyle(size: 24, circular: false))
            .help("刷新用量统计")
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    metricTile(title: "本月请求", value: "\(requests) 次", icon: "bolt.horizontal")
                    metricTile(title: "输入 / 输出 Token",
                               value: "\(compactNumber(inputTok)) / \(compactNumber(outputTok))",
                               icon: "character.cursor.ibeam")
                    metricTile(title: "平均首字耗时", value: avgTTFT, icon: "stopwatch")
                    metricTile(title: "估算花费",
                               value: cost.formatted(.currency(code: "USD").precision(.fractionLength(4))),
                               icon: "dollarsign.circle")
                }

                SnapAIFormDivider(inset: 0)

                HStack(spacing: 10) {
                    Text("月度预算提醒")
                        .font(SnapAIUI.Typography.bodyText.weight(.medium))
                    if let limit = table.monthlyBudgetUSD {
                        let ratio = Int(min(999, cost / limit * 100))
                        SnapAISemanticPill(title: cost >= limit ? "已达预算 ($\(String(format: "%.2f", limit)))" : "已用 \(ratio)% / $\(String(format: "%.2f", limit))",
                                           systemImage: cost >= limit ? "exclamationmark.triangle.fill" : "chart.pie",
                                           tone: cost >= limit ? .warning : .info)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text("$")
                            .font(SnapAIUI.Typography.metaText)
                            .foregroundStyle(.secondary)
                        TextField("不限", text: $budget)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(width: 76)
                            .accessibilityLabel("月预算，美元")
                            .onSubmit { saveBudget() }
                        Button("保存") { saveBudget() }
                            .buttonStyle(SnapAISecondaryButtonStyle(compact: true))
                    }
                }

                if let budgetError {
                    Text(budgetError)
                        .font(SnapAIUI.Typography.metaText)
                        .foregroundStyle(SnapAIUI.StatusColor.error)
                }

                if !rows.isEmpty || !month.isEmpty {
                    DisclosureGroup(isExpanded: $showDetails) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !rows.isEmpty {
                                ForEach(rows, id: \.providerID) { row in
                                    HStack {
                                        Text(row.displayName)
                                            .font(SnapAIUI.Typography.metaText.weight(.medium))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(row.requests) 次 · 成功率 \(row.successRateText) · 平均耗时 \(row.averageElapsedText)")
                                            .font(SnapAIUI.Typography.metaText)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                            if !dailyTotals.isEmpty {
                                SnapAIFormDivider(inset: 0)
                                ForEach(dailyTotals.prefix(14), id: \.day) { item in
                                    HStack {
                                        Text(item.day, format: .dateTime.month().day())
                                            .font(SnapAIUI.Typography.metaText)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(item.requests) 次 · \(item.tokens) tokens · $\(item.cost, specifier: "%.4f")")
                                            .font(SnapAIUI.Typography.metaText)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("按服务商与日期查看明细")
                            .font(SnapAIUI.Typography.metaText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
        .onAppear { reload() }
    }

    private func metricTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(SnapAIUI.Surface.quiet,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SnapAIUI.Surface.border, lineWidth: 0.6)
        }
    }

    private func compactNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fk", Double(n) / 1_000)
        }
        return "\(n)"
    }

    private func saveBudget() {
        let raw = budget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty || (Double(raw).map { $0.isFinite && $0 > 0 } ?? false) else {
            budgetError = "请输入大于 0 的数字，留空可取消预算提醒。"
            return
        }
        budgetError = nil
        RoutingMetricsStore.shared.setMonthlyBudgetUSD(Double(raw))
        reload()
    }

    private var dailyTotals: [(day: Date, requests: Int, tokens: Int, cost: Double)] {
        Dictionary(grouping: month, by: \.day).map { day, records in
            (day, records.reduce(0) { $0 + $1.requests },
             records.reduce(0) { $0 + $1.inputTokens + $1.outputTokens },
             records.reduce(0) { $0 + $1.estimatedUSD })
        }.sorted { $0.day > $1.day }
    }

    private func reload() {
        table = RoutingMetricsStore.shared.snapshot()
        budget = table.monthlyBudgetUSD.map { String($0) } ?? ""
    }
}
