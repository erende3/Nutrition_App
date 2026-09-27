//
//  Theme.swift
//  MyNutritionPal
//

import SwiftUI

// Colors are the named color sets in Assets.xcassets, each with a light and
// a dark value, used through Xcode's generated symbols: `Color.surface`,
// `.foregroundStyle(.textSecondary)`. The accent is the AccentColor set
// (`Color.accentColor`, and the tint of system controls). Text is sized by
// Dynamic Type text styles.

/// Corner radii: one for controls, one for cards.
enum Radius {
    /// Buttons, text fields, photo previews.
    static let control: CGFloat = 12
    /// Cards, list sections and banners.
    static let card: CGFloat = 16
}

extension View {
    /// Numbers: the rounded design, with equal-width digits so totals
    /// don't shift as they change.
    func numeric() -> some View {
        fontDesign(.rounded)
            .monospacedDigit()
    }
}
