import SwiftUI

public enum BeaverTheme {
    /// Primary brand blue — the accent used for record buttons, links, and selected states.
    public static let accent = Color(red: 0.0, green: 0.478, blue: 1.0) // #007AFF
    /// Deep navy used for headings and high-contrast text on light backgrounds.
    public static let navy = Color(red: 0.02, green: 0.161, blue: 0.294) // #05294B

    public static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    public static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    public static let cardCornerRadius: CGFloat = 16
    public static let pillCornerRadius: CGFloat = 22
}
