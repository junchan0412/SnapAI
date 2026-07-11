import Foundation
import Combine
import SnapAILogic

struct HistoryWindowPresentation {
    var criteria: HistoryFilterCriteria
    var entries: [HistoryEntry]
    var actionNames: [String]
    var modelNames: [String]
    var tagNames: [String]
    var canCreateContextProfile: Bool
    var totalCount: Int
}

final class HistoryWindowModel: ObservableObject {
    @Published var query = "" {
        didSet { criteriaDidChange(queryChanged: query != oldValue) }
    }
    @Published var actionFilter = HistoryFilterCriteria.allActions {
        didSet { criteriaDidChange() }
    }
    @Published var modelFilter = HistoryFilterCriteria.allModels {
        didSet { criteriaDidChange() }
    }
    @Published var tagFilter = HistoryFilterCriteria.allTags {
        didSet { criteriaDidChange() }
    }
    @Published var favoriteOnly = false {
        didSet { criteriaDidChange() }
    }
    @Published private(set) var presentation: HistoryWindowPresentation
    @Published private(set) var savedFilters: [SavedHistoryFilter]
    @Published private(set) var isRefreshing = false
    var tagDrafts: [String: String] = [:]

    private var sourceEntries: [HistoryEntry]
    private var sourceLimit: Int
    private var refreshGeneration: UInt64 = 0
    private var refreshWorkItem: DispatchWorkItem?
    private var suppressCriteriaRefresh = false
    private var cancellables = Set<AnyCancellable>()
    private let refreshQueue = DispatchQueue(label: "com.snapai.history-window-refresh",
                                             qos: .userInitiated)

    init(settings: AppSettings) {
        sourceEntries = settings.history
        sourceLimit = settings.historyLimit
        savedFilters = settings.savedHistoryFilters
        presentation = Self.makePresentation(criteria: HistoryFilterCriteria(),
                                             entries: settings.history,
                                             limit: settings.historyLimit)

        settings.$history
            .combineLatest(settings.$historyLimit)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries, limit in
                guard let self else { return }
                self.sourceEntries = entries
                self.sourceLimit = limit
                self.scheduleRefresh(delay: 0)
            }
            .store(in: &cancellables)

        settings.$savedHistoryFilters
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] filters in
                self?.savedFilters = filters
            }
            .store(in: &cancellables)
    }

    deinit {
        refreshWorkItem?.cancel()
    }

    func resetFilters() {
        apply(criteria: HistoryFilterCriteria())
    }

    func apply(criteria: HistoryFilterCriteria) {
        suppressCriteriaRefresh = true
        query = criteria.query
        actionFilter = criteria.actionFilter
        modelFilter = criteria.modelFilter
        tagFilter = criteria.tagFilter
        favoriteOnly = criteria.favoriteOnly
        suppressCriteriaRefresh = false
        scheduleRefresh(delay: 0)
    }

    var criteria: HistoryFilterCriteria {
        HistoryFilterCriteria(query: query,
                              actionFilter: actionFilter,
                              modelFilter: modelFilter,
                              tagFilter: tagFilter,
                              favoriteOnly: favoriteOnly)
    }

    func refreshImmediately() {
        scheduleRefresh(delay: 0)
    }

    private func criteriaDidChange(queryChanged: Bool = false) {
        guard !suppressCriteriaRefresh else { return }
        scheduleRefresh(delay: HistoryWindowRefreshPolicy.delay(queryChanged: queryChanged))
    }

    private func scheduleRefresh(delay: TimeInterval) {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshWorkItem?.cancel()
        if !isRefreshing {
            isRefreshing = true
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.startRefresh(generation: generation)
        }
        refreshWorkItem = workItem
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }

    private func startRefresh(generation: UInt64) {
        let criteria = criteria
        let entries = sourceEntries
        let limit = sourceLimit
        refreshQueue.async { [weak self] in
            let presentation = Self.makePresentation(criteria: criteria,
                                                       entries: entries,
                                                       limit: limit)
            DispatchQueue.main.async {
                guard let self,
                      HistoryWindowRefreshPolicy.shouldPublish(requestGeneration: generation,
                                                               latestGeneration: self.refreshGeneration) else {
                    return
                }
                self.presentation = presentation
                self.isRefreshing = false
            }
        }
    }

    private static func makePresentation(criteria: HistoryFilterCriteria,
                                         entries: [HistoryEntry],
                                         limit: Int) -> HistoryWindowPresentation {
        let filtered = HistorySearch.filteredEntries(criteria: criteria,
                                                      memoryEntries: entries,
                                                      limit: limit,
                                                      searchStore: HistoryStore.shared.search)
        return HistoryWindowPresentation(
            criteria: criteria,
            entries: filtered,
            actionNames: facetOptions(allValue: HistoryFilterCriteria.allActions,
                                      values: entries.map(\.displayActionName),
                                      currentValue: criteria.actionFilter),
            modelNames: facetOptions(allValue: HistoryFilterCriteria.allModels,
                                     values: entries.map(\.displayModelFilterName),
                                     currentValue: criteria.modelFilter),
            tagNames: facetOptions(allValue: HistoryFilterCriteria.allTags,
                                   values: entries.flatMap(\.displayTags),
                                   currentValue: criteria.tagFilter),
            canCreateContextProfile: filtered.contains(where: HistoryContextProfileBuilder.isUsableForContext),
            totalCount: entries.count
        )
    }

    private static func facetOptions(allValue: String,
                                     values: [String],
                                     currentValue: String) -> [String] {
        var options = [allValue] + HistoryFilterCriteria.facetValues(values)
        if currentValue != allValue,
           HistoryFilterCriteria.normalizedFacetValue(currentValue) != nil,
           !options.contains(currentValue) {
            options.append(currentValue)
        }
        return options
    }
}
