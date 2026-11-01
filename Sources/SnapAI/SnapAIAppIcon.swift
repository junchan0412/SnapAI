import SwiftUI

struct SnapAIAppIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image = NSImage(named: colorScheme == .dark ? "AppIconDark" : "AppIconLight") {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "text.bubble.fill").resizable().scaledToFit().padding(6)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("SnapAI")
    }
}
