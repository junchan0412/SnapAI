import Foundation

public enum SystemPrivacyPane: String, Equatable {
    case accessibility = "Privacy_Accessibility"
    case screenCapture = "Privacy_ScreenCapture"
}

public enum SystemPrivacySettings {
    private static let securityPreferenceBase = "x-apple.systempreferences:com.apple.preference.security"

    public static func url(for pane: SystemPrivacyPane) -> URL {
        URL(string: "\(securityPreferenceBase)?\(pane.rawValue)")!
    }

    public static var accessibilityURL: URL {
        url(for: .accessibility)
    }

    public static var screenCaptureURL: URL {
        url(for: .screenCapture)
    }
}
