import Foundation
import SnapAILogic

extension HistoryEntry {
    var historyExportCommandInput: HistoryExportCommandInput {
        HistoryExportCommandInput(displayActionName: displayActionName,
                                  displayModelFilterName: displayModelFilterName,
                                  displayTags: displayTags,
                                  isFavorite: isFavorite)
    }

    var historyContextCommandInput: HistoryContextCommandInput {
        HistoryContextCommandInput(displayActionName: displayActionName,
                                   displayModelFilterName: displayModelFilterName,
                                   displayTags: displayTags,
                                   isFavorite: isFavorite,
                                   isUsableForContext: HistoryContextProfileBuilder.isUsableForContext(self))
    }
}

extension HistoryExportCommandCriteria {
    var historyFilterCriteria: HistoryFilterCriteria {
        HistoryFilterCriteria(actionFilter: actionFilter ?? HistoryFilterCriteria.allActions,
                              modelFilter: modelFilter ?? HistoryFilterCriteria.allModels,
                              tagFilter: tagFilter ?? HistoryFilterCriteria.allTags,
                              favoriteOnly: favoriteOnly)
    }
}

extension HistoryContextCommandCriteria {
    var historyFilterCriteria: HistoryFilterCriteria {
        HistoryFilterCriteria(actionFilter: actionFilter ?? HistoryFilterCriteria.allActions,
                              modelFilter: modelFilter ?? HistoryFilterCriteria.allModels,
                              tagFilter: tagFilter ?? HistoryFilterCriteria.allTags,
                              favoriteOnly: favoriteOnly)
    }
}
