import AppKit
import SnapAILogic
import SwiftUI

@MainActor
enum SnapAIAppIconResolver {
    private static var cache: [String: NSImage] = [:]

    static func image(style: AppIconStyle,
                      appearance: AppIconAppearance,
                      systemIsDark: Bool) -> NSImage? {
        let isDark = appearance.resolvesToDark(systemIsDark: systemIsDark)
        return image(style: style, isDark: isDark)
    }

    static func image(style: AppIconStyle, isDark: Bool) -> NSImage? {
        let name = style.resourceName(isDark: isDark)
        if let cached = cache[name] {
            return cached
        }
        if let bundled = NSImage(named: name) {
            cache[name] = bundled
            return bundled
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let loaded = NSImage(contentsOf: url) {
            cache[name] = loaded
            return loaded
        }
        let devURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Resources/\(name).png")
        if let devLoaded = NSImage(contentsOf: devURL) {
            cache[name] = devLoaded
            return devLoaded
        }
        let fallbackName = isDark ? "AppIconDark" : "AppIconLight"
        if let fallback = NSImage(named: fallbackName) {
            return fallback
        }
        return nil
    }
}

struct SnapAIAppIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var settings: AppSettings = .shared
    var size: CGFloat = 40
    var styleOverride: AppIconStyle? = nil
    var isDarkOverride: Bool? = nil

    private var resolvedImage: NSImage? {
        let style = styleOverride ?? settings.appIconStyle
        if let isDarkOverride {
            return SnapAIAppIconResolver.image(style: style, isDark: isDarkOverride)
        }
        return SnapAIAppIconResolver.image(
            style: style,
            appearance: settings.appIconAppearance,
            systemIsDark: colorScheme == .dark
        )
    }

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("SnapAI")
    }
}
