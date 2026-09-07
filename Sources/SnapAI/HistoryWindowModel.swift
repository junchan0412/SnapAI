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
    private let historyStore: HistoryStore
    private var sourceRevision: UInt64 = 0
    private var refreshGeneration: UInt64 = 0
    private var refreshWorkItem: DispatchWorkItem?
    private var isComputing = false
    private var readyGeneration: UInt64?
    private var facetRevision: UInt64?
    private var cachedFacets = (actions: [String](), models: [String](), tags: [String]())
    private var suppressCriteriaRefresh = false
    private var cancellables = Set<AnyCancellable>()
    private let refreshQueue = DispatchQueue(label: "com.snapai.history-window-refresh",
                                             qos: .userInitiated)

    init(settings: AppSettings) {
        sourceEntries = settings.history
        sourceLimit = settings.historyLimit
        historyStore = settings.persistenceHistoryStore
        savedFilters = settings.savedHistoryFilters
        presentation = HistoryWindowPresentation(criteria: HistoryFilterCriteria(),
                                                   entries: settings.history,
                                                   actionNames: [HistoryFilterCriteria.allActions],
                                                   modelNames: [HistoryFilterCriteria.allModels],
                                                   tagNames: [HistoryFilterCriteria.allTags],
                                                   canCreateContextProfile: settings.history.contains(where: HistoryContextProfileBuilder.isUsableForContext),
                                                   totalCount: settings.history.count)

        settings.$history
            .combineLatest(settings.$historyLimit)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries, limit in
                guard let self else { return }
                self.sourceEntries = entries
                self.sourceLimit = limit
                self.sourceRevision &+= 1
                self.scheduleRefresh(delay: 0)
            }
            .store(in: &cancellables)

        scheduleRefresh(delay: 0)

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
        readyGeneration = nil
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
        guard generation == refreshGeneration else { return }
        guard !isComputing else {
            readyGeneration = generation
            return
        }
        isComputing = true
        readyGeneration = nil
        let criteria = criteria
        let entries = sourceEntries
        let limit = sourceLimit
        let revision = sourceRevision
        refreshQueue.async { [weak self] in
            guard let self else { return }
            if self.facetRevision != revision {
                self.cachedFacets = (HistoryFilterCriteria.facetValues(entries.map(\.displayActionName)),
                                     HistoryFilterCriteria.facetValues(entries.map(\.displayModelFilterName)),
                                     HistoryFilterCriteria.facetValues(entries.flatMap(\.displayTags)))
                self.facetRevision = revision
            }
            let presentation = Self.makePresentation(criteria: criteria,
                                                      entries: entries,
                                                      limit: limit,
                                                      facets: self.cachedFacets,
                                                      store: self.historyStore)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isComputing = false
                if HistoryWindowRefreshPolicy.shouldPublish(requestGeneration: generation,
                                                           latestGeneration: self.refreshGeneration) {
                    self.presentation = presentation
                    self.isRefreshing = false
                }
                if let ready = self.readyGeneration {
                    self.readyGeneration = nil
                    self.startRefresh(generation: ready)
                }
            }
        }
    }

    private static func makePresentation(criteria: HistoryFilterCriteria,
                                         entries: [HistoryEntry],
                                         limit: Int,
                                         facets: (actions: [String], models: [String], tags: [String]),
                                         store: HistoryStore) -> HistoryWindowPresentation {
        let filtered = HistorySearch.filteredEntries(criteria: criteria,
                                                      memoryEntries: entries,
                                                      limit: limit,
                                                      searchStore: store.search)
        return HistoryWindowPresentation(
            criteria: criteria,
            entries: filtered,
            actionNames: facetOptions(allValue: HistoryFilterCriteria.allActions,
                                      values: facets.actions,
                                      currentValue: criteria.actionFilter),
            modelNames: facetOptions(allValue: HistoryFilterCriteria.allModels,
                                     values: facets.models,
                                     currentValue: criteria.modelFilter),
            tagNames: facetOptions(allValue: HistoryFilterCriteria.allTags,
                                   values: facets.tags,
                                   currentValue: criteria.tagFilter),
            canCreateContextProfile: filtered.contains(where: HistoryContextProfileBuilder.isUsableForContext),
            totalCount: entries.count
        )
    }

    private static func facetOptions(allValue: String,
                                     values: [String],
                                     currentValue: String) -> [String] {
        var options = [allValue] + values
        if currentValue != allValue,
           HistoryFilterCriteria.normalizedFacetValue(currentValue) != nil,
           !options.contains(currentValue) {
            options.append(currentValue)
        }
        return options
    }
}
