import SwiftUI

enum DesignTokens {
    enum Spacing {
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 20
        static let bottomPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let footerVerticalPadding: CGFloat = 10
        static let controlSpacing: CGFloat = 12
        static let compactSpacing: CGFloat = 8
    }

    enum Corner {
        static let card: CGFloat = 12
        static let banner: CGFloat = 12
        static let inner: CGFloat = 8
        static let segment: CGFloat = 6
    }

    enum Card {
        static let padding: CGFloat = 22
    }

    enum Layout {
        static let windowMinHeight: CGFloat = 600
        static let dropZoneMinHeight: CGFloat = 120
        static let dropZoneMaxHeight: CGFloat = 220
    }

    enum Colors {
        static func border(_ colorScheme: ColorScheme, increasedContrast: Bool = false) -> Color {
            if increasedContrast {
                return Color.primary.opacity(colorScheme == .dark ? 0.4 : 0.25)
            }
            return Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.12)
        }

        static func hoverFill(_ colorScheme: ColorScheme) -> Color {
            Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
        }

        static func dropShadow(_ colorScheme: ColorScheme, isHovered: Bool) -> Color {
            if colorScheme == .dark {
                return Color.black.opacity(isHovered ? 0.55 : 0.4)
            }
            return Color.black.opacity(isHovered ? 0.12 : 0.08)
        }

        static func toastShadow(_ colorScheme: ColorScheme) -> Color {
            colorScheme == .dark
                ? Color.black.opacity(0.55)
                : Color.black.opacity(0.14)
        }

        static let warning = Color.orange
        static let success = Color.green
        static let error = Color.red

        /// With Reduce Transparency, use the opaque window background color.
        /// Normally .regularMaterial is used, so this value serves as a substitute background color.
        static let opaqueSurface = Color(NSColor.windowBackgroundColor)
    }

    enum Icon {
        static let hero: CGFloat = 44
        static let status: CGFloat = 20
        static let compact: CGFloat = 14
    }
}
