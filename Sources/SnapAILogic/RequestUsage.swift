import Foundation

package struct RequestUsageDay: Codable, Equatable, Identifiable {
    package var providerID: String
    package var modelName: String
    package var day: Date
    package var requests = 0
    package var inputTokens = 0
    package var outputTokens = 0
    package var usageSamples = 0
    package var estimatedUSD = 0.0
    package var pricedSamples = 0
    package var firstTokenTotalMilliseconds = 0
    package var firstTokenSamples = 0
    package var networkTotalMilliseconds = 0
    package var id: String { "\(providerID)::\(modelName)::\(day.timeIntervalSince1970)" }

    package mutating func record(usage: AIUsage?, estimatedUSD: Double?,
                                 firstTokenMilliseconds: Int?, networkMilliseconds: Int) {
        requests += 1
        if let usage, usage.isComplete, let input = usage.inputTokens, let output = usage.outputTokens {
            inputTokens += max(0, input)
            outputTokens += max(0, output)
            usageSamples += 1
        }
        if let estimatedUSD, estimatedUSD.isFinite, estimatedUSD >= 0 {
            self.estimatedUSD += estimatedUSD
            pricedSamples += 1
        }
        if let firstTokenMilliseconds {
            firstTokenTotalMilliseconds += max(0, firstTokenMilliseconds)
            firstTokenSamples += 1
        }
        networkTotalMilliseconds += max(0, networkMilliseconds)
    }
}

extension RoutingMetricsTable {
    package mutating func recordUsage(route: AIRequestRoute, usage: AIUsage?, estimatedUSD: Double?,
                                     firstTokenMilliseconds: Int?, networkMilliseconds: Int,
                                     at date: Date = Date(), calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        var value = RequestUsageDay(providerID: route.providerID, modelName: route.modelName, day: day)
        value = dailyUsage?[value.id] ?? value
        value.record(usage: usage, estimatedUSD: estimatedUSD,
                     firstTokenMilliseconds: firstTokenMilliseconds, networkMilliseconds: networkMilliseconds)
        var days = dailyUsage ?? [:]
        days[value.id] = value
        let oldest = calendar.date(byAdding: .day, value: -400, to: day) ?? .distantPast
        dailyUsage = days.filter { $0.value.day >= oldest }
    }
}

extension RoutingMetricsStore {
    package func recordUsage(route: AIRequestRoute, usage: AIUsage?, pricing: ModelPricing?,
                             firstTokenMilliseconds: Int?, networkMilliseconds: Int) {
        let cost: Double?
        if usage?.isComplete == true, let input = usage?.inputTokens, let output = usage?.outputTokens {
            cost = pricing?.estimatedCost(inputTokens: input, outputTokens: output)
        } else { cost = nil }
        update { table in
            table.recordUsage(route: route, usage: usage, estimatedUSD: cost,
                              firstTokenMilliseconds: firstTokenMilliseconds, networkMilliseconds: networkMilliseconds)
        }
    }

    package func setMonthlyBudgetUSD(_ budget: Double?) {
        update { table in
            table.monthlyBudgetUSD = budget.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        }
    }
}

extension UsageDashboard {
    package static func currentMonth(table: RoutingMetricsTable, now: Date = Date(),
                                     calendar: Calendar = .current) -> [RequestUsageDay] {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return [] }
        return (table.dailyUsage ?? [:]).values.filter { interval.contains($0.day) && $0.day <= now }
            .sorted { $0.day == $1.day ? $0.id < $1.id : $0.day < $1.day }
    }
}
