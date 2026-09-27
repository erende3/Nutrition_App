//
//  Components.swift
//  MyNutritionPal
//

import SwiftUI

extension View {
    /// A card: the surface color, with a hairline border in light
    /// appearance (none in dark, where the surface stands out enough).
    func cardSurface() -> some View {
        background(.surface, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(.cardBorder)
            )
    }
}

/// The screen's main action: an accent fill. Disabled (including while
/// working), a plain fill with secondary text. Callers make the label
/// full width when the button should be.
struct PrimaryButtonStyle: ButtonStyle {
    /// 50 for full-width actions; at least 44, the minimum tap target.
    var minHeight: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, minHeight: minHeight)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let minHeight: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(isEnabled ? Color.onAccent : Color.textSecondary)
                .padding(.horizontal, 20)
                .frame(minHeight: minHeight)
                .background(
                    isEnabled ? Color.accentColor : Color.fieldFill,
                    in: RoundedRectangle(cornerRadius: Radius.control)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.control))
                .opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}

/// An error next to what it's about: text with an icon, so it isn't told
/// apart by color alone.
struct InlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.danger)
    }
}
