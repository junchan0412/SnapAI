import Foundation

public enum HistoryWindowRefreshPolicy {
    public static let queryDebounceInterval: TimeInterval = 0.18

    public static func delay(queryChanged: Bool) -> TimeInterval {
        queryChanged ? queryDebounceInterval : 0
    }

    public static func shouldPublish(requestGeneration: UInt64,
                                     latestGeneration: UInt64) -> Bool {
        requestGeneration == latestGeneration
    }
}
