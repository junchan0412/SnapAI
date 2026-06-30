import SwiftUI

enum SnapAIUI {
    static let panelRadius: CGFloat = 8
    static let cardRadius: CGFloat = 7
    static let controlRadius: CGFloat = 6
    static let compactPadding: CGFloat = 8
    static let sectionPadding: CGFloat = 9

    static let quietFillOpacity: Double = 0.028
    static let regularFillOpacity: Double = 0.04
    static let selectedFillOpacity: Double = 0.12
    static let strokeOpacity: Double = 0.075
}

private struct SnapAISurfaceModifier: ViewModifier {
    var padding: CGFloat
    var fillOpacity: Double
    var strokeOpacity: Double
    var radius: CGFloat
    var isSelected: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(SnapAIUI.selectedFillOpacity) : Color.primary.opacity(fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.34) : Color.primary.opacity(strokeOpacity), lineWidth: 1)
            }
    }
}

extension View {
    func snapAISurface(padding: CGFloat = SnapAIUI.sectionPadding,
                       fillOpacity: Double = SnapAIUI.regularFillOpacity,
                       strokeOpacity: Double = SnapAIUI.strokeOpacity,
                       radius: CGFloat = SnapAIUI.cardRadius,
                       isSelected: Bool = false) -> some View {
        modifier(SnapAISurfaceModifier(padding: padding,
                                       fillOpacity: fillOpacity,
                                       strokeOpacity: strokeOpacity,
                                       radius: radius,
                                       isSelected: isSelected))
    }
}

struct SnapAIStatusPill: View {
    var title: String
    var systemImage: String
    var tint: Color = .secondary
    var filled: Bool = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(filled ? tint.opacity(0.14) : Color.primary.opacity(0.045), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(filled ? tint.opacity(0.24) : Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct SnapAIIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = 26
    var circular: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(isEnabled ? Color.secondary : Color.secondary.opacity(0.45))
            .background {
                Group {
                    if circular {
                        Circle()
                            .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.055))
                    } else {
                        RoundedRectangle(cornerRadius: SnapAIUI.controlRadius, style: .continuous)
                            .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.055))
                    }
                }
            }
            .contentShape(Rectangle())
    }
}

