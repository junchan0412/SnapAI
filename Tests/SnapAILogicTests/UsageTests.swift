import Foundation
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func testUsageDecodingAndTrailingEvents() {
    func event(_ payload: String) -> ServerSentEvent { ServerSentEvent(data: payload) }
    do {
        var decoder = AIStreamDecoder(apiProtocol: .openAI)
        _ = try decoder.decode(event(#"{"choices":[{"delta":{"content":"done"},"finish_reason":"stop"}]}"#))
        expect(decoder.isFinished && !decoder.streamTerminated, "finish_reason permits trailing usage")
        let delta = try decoder.decode(event(#"{"choices":[],"usage":{"prompt_tokens":123,"completion_tokens":45,"prompt_tokens_details":{"cached_tokens":12}}}"#))
        expect(delta.usage?.inputTokens == 123 && delta.usage?.outputTokens == 45 && delta.usage?.cachedInputTokens == 12,
               "OpenAI usage after finish_reason is preserved")
        expect(!delta.isEmpty, "usage-only delta is delivered")
        let ignored = try decoder.decode(event(#"{"choices":[{"delta":{"content":"late text"}}]}"#))
        expect(ignored.content.isEmpty, "completed content rejects late text")
        _ = try decoder.decode(event("[DONE]"))
        expect(decoder.streamTerminated, "DONE terminates stream")
        try decoder.validateCompletion()
        let late = try decoder.decode(event(#"{"usage":{"prompt_tokens":999}}"#))
        expect(late.usage == nil, "terminal stream rejects duplicate usage")
        var anthropic = AIStreamDecoder(apiProtocol: .anthropic)
        let first = try anthropic.decode(event(#"{"type":"message_start","message":{"usage":{"input_tokens":100,"output_tokens":0,"cache_read_input_tokens":30,"cache_creation_input_tokens":20}}}"#))
        var usage = first.usage!
        expect(!usage.isComplete, "Anthropic message_start counts are provisional until final message_delta")
        _ = try anthropic.decode(event(#"{"type":"content_block_delta","delta":{"text":"answer"}}"#))
        let last = try anthropic.decode(event(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":21}}"#))
        usage.merge(last.usage!)
        expect(usage.inputTokens == 150 && usage.outputTokens == 21 && usage.cachedInputTokens == 30 && usage.isComplete,
               "Anthropic cumulative output replaces initial zero and includes cached input")
        _ = try anthropic.decode(event(#"{"type":"message_stop"}"#))
        try anthropic.validateCompletion()
        expect(anthropic.streamTerminated, "Anthropic message_stop terminates")
        expect(AIUsage.parse(["prompt_tokens": -1, "completion_tokens": true], apiProtocol: .openAI) == nil,
               "invalid usage does not become a fabricated token count")
        expect(AIUsage.parse(["prompt_tokens": 1.5], apiProtocol: .openAI) == nil,
               "fractional token counts are rejected")
        var usageWithoutReason = AIStreamDecoder(apiProtocol: .openAI)
        _ = try usageWithoutReason.decode(event(#"{"choices":[{"delta":{"content":"answer"}}]}"#))
        let terminalUsage = try usageWithoutReason.decode(event(#"{"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5}}"#))
        _ = try usageWithoutReason.decode(event("[DONE]"))
        try usageWithoutReason.validateCompletion()
        expect(terminalUsage.usage?.isComplete == true,
               "terminal usage-only event is final even when a compatible server omits finish_reason")
        var noUsage = AIStreamDecoder(apiProtocol: .openAI)
        let output = try noUsage.decode(event(#"{"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}"#))
        try noUsage.validateCompletion()
        expect(output.usage == nil, "compatible servers without usage remain supported")
    } catch { expect(false, "usage decoding failed: \(error)") }
}

func testUsageBudgetAndDailyPersistence() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!
    let route = AIRequestRoute(providerID: "fixture", providerName: "fixture", modelName: "model", reason: "fixture")
    var table = RoutingMetricsTable.empty
    table.monthlyBudgetUSD = 10
    table.recordUsage(route: route, usage: AIUsage(inputTokens: 100, outputTokens: 20), estimatedUSD: 0.05,
                      firstTokenMilliseconds: 15, networkMilliseconds: 80, at: now, calendar: calendar)
    table.recordUsage(route: route, usage: nil, estimatedUSD: nil,
                      firstTokenMilliseconds: nil, networkMilliseconds: 40, at: now, calendar: calendar)
    let month = UsageDashboard.currentMonth(table: table, now: now, calendar: calendar)
    expect(month.count == 1 && month[0].requests == 2, "daily metrics aggregate attempts")
    expect(month[0].usageSamples == 1 && month[0].inputTokens == 100 && month[0].outputTokens == 20,
           "missing usage is counted separately from actual zero")
    expect(month[0].pricedSamples == 1 && month[0].estimatedUSD == 0.05 && month[0].firstTokenSamples == 1,
           "cost and TTFT retain independent sample counts")
    do {
        let encoded = try JSONEncoder().encode(table)
        let restored = try JSONDecoder().decode(RoutingMetricsTable.self, from: encoded)
        expect(restored == table, "usage and budget persist without request content")
        let old = try JSONDecoder().decode(RoutingMetricsTable.self, from: Data(#"{"records":{}}"#.utf8))
        expect(old.dailyUsage == nil && old.monthlyBudgetUSD == nil, "legacy routing records decode without new fields")
    } catch { expect(false, "usage persistence failed: \(error)") }
    let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
    table.recordUsage(route: route, usage: nil, estimatedUSD: nil, firstTokenMilliseconds: nil,
                      networkMilliseconds: 1, at: september, calendar: calendar)
    expect(UsageDashboard.currentMonth(table: table, now: now, calendar: calendar).count == 1,
           "monthly budget excludes the previous month")
    var provisional = AIUsage(inputTokens: 100, outputTokens: 0)
    provisional.isFinal = false
    var incomplete = RequestUsageDay(providerID: "anthropic", modelName: "fixture", day: now)
    incomplete.record(usage: provisional, estimatedUSD: nil, firstTokenMilliseconds: 12, networkMilliseconds: 30)
    expect(incomplete.requests == 1 && incomplete.usageSamples == 0,
           "cancelled provisional Anthropic counts are not labeled final usage")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = RoutingMetricsStore(url: root, saveHandler: { _, _ in })
    store.setMonthlyBudgetUSD(12.5)
    expect(store.snapshot().monthlyBudgetUSD == 12.5, "budget can be configured")
    store.setMonthlyBudgetUSD(.infinity)
    expect(store.snapshot().monthlyBudgetUSD == nil, "non-finite budget is rejected")
    store.setMonthlyBudgetUSD(nil)
    expect(store.snapshot().monthlyBudgetUSD == nil, "budget can be cleared")
}
