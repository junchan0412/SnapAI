import SwiftUI
import SnapAILogic

struct RequestUsageDashboardView: View {
    @ObservedObject var settings: AppSettings
    @State private var table = RoutingMetricsStore.shared.snapshot()
    @State private var budget = ""
    @State private var budgetError: String?

    private var month: [RequestUsageDay] { UsageDashboard.currentMonth(table: table) }

    var body: some View {
        let names = Dictionary(uniqueKeysWithValues: settings.providers.map { ($0.id, $0.name) })
        let rows = UsageDashboard.rows(table: table, providerNames: names)
        let requests = month.reduce(0) { $0 + $1.requests }
        let samples = month.reduce(0) { $0 + $1.usageSamples }
        let priced = month.reduce(0) { $0 + $1.pricedSamples }
        let cost = month.reduce(0) { $0 + $1.estimatedUSD }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("使用统计").font(SnapAIUI.Typography.sectionTitle)
                Spacer()
                Button("刷新") { reload() }
                    .buttonStyle(.borderless)
            }
            if rows.isEmpty && month.isEmpty {
                Text("暂无请求记录，完成一次提问后可查看用量。")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.providerID) { row in
                HStack {
                    Text(row.displayName).lineLimit(1)
                    Spacer()
                    Text("\(row.requests) 次 · 成功率 \(row.successRateText) · API 平均 \(row.averageElapsedText)")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Divider()
            Text("本月 · \(requests) 次请求尝试（含取消）").fontWeight(.medium)
            Text("API 返回 token：输入 \(month.reduce(0) { $0 + $1.inputTokens }) / 输出 \(month.reduce(0) { $0 + $1.outputTokens }) · \(samples)/\(requests) 次有完整用量")
                .monospacedDigit()
            HStack {
                Text("估算费用：\(cost, format: .currency(code: "USD").precision(.fractionLength(4)))")
                Text("\(priced)/\(requests) 次可计价").foregroundStyle(.secondary)
            }
            let firstSamples = month.reduce(0) { $0 + $1.firstTokenSamples }
            if firstSamples > 0 {
                Text("TTFT 平均 \(month.reduce(0) { $0 + $1.firstTokenTotalMilliseconds } / firstSamples) ms（首段正文或思考）")
            }
            if requests > 0 {
                Text("API 平均 \(month.reduce(0) { $0 + $1.networkTotalMilliseconds } / requests) ms，不含逐字展示和 Markdown 排版")
            }
            HStack {
                Text("月预算 USD")
                TextField("未设置", text: $budget).frame(width: 85)
                    .accessibilityLabel("月预算，美元")
                Button("保存") {
                    let raw = budget.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard raw.isEmpty || (Double(raw).map { $0.isFinite && $0 > 0 } ?? false) else {
                        budgetError = "请输入大于 0 的金额，留空可取消预算。"
                        return
                    }
                    budgetError = nil
                    RoutingMetricsStore.shared.setMonthlyBudgetUSD(Double(raw))
                    reload()
                }
                if let limit = table.monthlyBudgetUSD {
                    Text(cost >= limit ? "已达预算" : "已用 \(Int(min(999, cost / limit * 100)))%")
                        .foregroundStyle(cost >= limit ? .orange : .secondary)
                }
            }
            if let budgetError { Text(budgetError).foregroundStyle(.red) }
            Text("费用按请求时的手工单价估算，含缓存的输入按普通输入价计算；不是账单。缺少 usage 或单价的请求不计入费用，预算仅作提醒。按日记录保留 400 天，不保存请求正文。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !month.isEmpty {
                DisclosureGroup("本月每日用量") {
                    ForEach(dailyTotals, id: \.day) { item in
                        HStack {
                            Text(item.day, format: .dateTime.month().day())
                            Spacer()
                            Text("\(item.requests) 次 · \(item.tokens) tokens · $\(item.cost, specifier: "%.4f")")
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .font(SnapAIUI.Typography.metaText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SnapAIUI.compactPadding)
        .snapAIGlassCard()
        .onAppear { reload() }
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
