import Foundation
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func historyExportCommandInputs(_ history: [HistoryEntry]) -> [HistoryExportCommandInput] {
    history.map { entry in
        HistoryExportCommandInput(displayActionName: entry.displayActionName,
                                  displayModelFilterName: entry.displayModelFilterName,
                                  displayTags: entry.displayTags,
                                  isFavorite: entry.isFavorite)
    }
}
