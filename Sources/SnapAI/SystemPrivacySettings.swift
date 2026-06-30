import Foundation

enum SystemPrivacyPane: String, Equatable {
    case accessibility = "Privacy_Accessibility"
    case screenCapture = "Privacy_ScreenCapture"
}

enum SystemPrivacySettings {
    private static let securityPreferenceBase = "x-apple.systempreferences:com.apple.preference.security"

    static func url(for pane: SystemPrivacyPane) -> URL {
        URL(string: "\(securityPreferenceBase)?\(pane.rawValue)")!
    }

    static var accessibilityURL: URL {
        url(for: .accessibility)
    }

    static var screenCaptureURL: URL {
        url(for: .screenCapture)
    }
}
