import SwiftUI

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    var icon: String
    var action: (label: String, handler: @Sendable () -> Void)?
}

extension ToastMessage: Equatable {
    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        // `handler` is a closure and cannot be compared, so it is ignored
        lhs.id == rhs.id
            && lhs.text == rhs.text
            && lhs.icon == rhs.icon
    }
}
struct ToastView: View {
    let message: ToastMessage
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.compactSpacing) {
            Image(systemName: message.icon)
                .foregroundStyle(DesignTokens.Colors.success)
            Text(message.text)
                .font(.subheadline)
            if let action = message.action {
                Button(action.label, action: action.handler)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(action.label)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sectionSpacing)
        .padding(.vertical, DesignTokens.Spacing.footerVerticalPadding)
        .background(
            reduceTransparency ? AnyShapeStyle(DesignTokens.Colors.opaqueSurface) : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: DesignTokens.Corner.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Corner.card, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
        }
        .shadow(color: DesignTokens.Colors.toastShadow(colorScheme), radius: 8, y: 2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel(message.text)
    }
}
