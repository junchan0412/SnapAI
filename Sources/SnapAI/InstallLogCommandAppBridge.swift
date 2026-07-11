import Foundation
import SnapAILogic

extension UpdateChecker.InstallLogStatus {
    var permissionHealthStatus: PermissionInstallLogStatus {
        PermissionInstallLogStatus(
            diagnosticPath: diagnosticPath,
            isAvailable: url != nil,
            diagnosticCode: diagnosticCode,
            recoverySuggestion: recoverySuggestion
        )
    }

    var installLogCommandStatus: InstallLogCommandStatus {
        switch self {
        case .noRecord:
            return .noRecord
        case .untrustedLocation(let path):
            return .untrustedLocation(path)
        case .missing(let path):
            return .missing(path)
        case .available(let url):
            return .available(url)
        }
    }
}
