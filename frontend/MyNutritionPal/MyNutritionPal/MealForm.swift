//
//  MealForm.swift
//  MyNutritionPal
//

import Foundation

/// The Edit Meal form: the text in each field, what's wrong with it, and
/// the changes Save sends. Limits are input sanity (Milestone 0.12, E7), not
/// nutrition policy; the server checks them again.
///
/// Only fields whose text was changed are checked and sent, so a stored
/// value the form can't show exactly (more than one decimal) is never
/// rounded by saving another field.
struct MealForm: Equatable {
    enum Field: CaseIterable {
        case name, calories, protein, carbs, fat
    }

    var name: String
    var calories: String
    var protein: String
    var carbs: String
    var fat: String

    private let original: Meal
    private let locale: Locale

    init(meal: Meal, locale: Locale = .autoupdatingCurrent) {
        original = meal
        self.locale = locale
        name = meal.meal_name
        calories = String(meal.calories)
        protein = Self.gramsText(meal.protein_g, locale: locale)
        carbs = Self.gramsText(meal.carbohydrates_g, locale: locale)
        fat = Self.gramsText(meal.fat_g, locale: locale)
    }

    subscript(field: Field) -> String {
        get {
            switch field {
            case .name: name
            case .calories: calories
            case .protein: protein
            case .carbs: carbs
            case .fat: fat
            }
        }
        set {
            switch field {
            case .name: name = newValue
            case .calories: calories = newValue
            case .protein: protein = newValue
            case .carbs: carbs = newValue
            case .fat: fat = newValue
            }
        }
    }

    /// True once any field's text differs from how the form opened.
    var isDirty: Bool {
        Field.allCases.contains { self[$0] != MealForm(meal: original, locale: locale)[$0] }
    }

    /// Why a changed field can't be saved; nil when it can (or is unchanged).
    func error(for field: Field) -> String? {
        guard isEdited(field) else { return nil }
        switch parse(field) {
        case .success: return nil
        case .failure(let problem): return problem.message
        }
    }

    var isValid: Bool {
        Field.allCases.allSatisfy { error(for: $0) == nil }
    }

    /// The edit to send: only changed, valid fields whose value really
    /// differs. Nil when there's nothing to save or something is invalid.
    var changes: MealChanges? {
        guard isValid else { return nil }
        var changes = MealChanges()
        for field in Field.allCases where isEdited(field) {
            guard case .success(let value) = parse(field) else { continue }
            switch (field, value) {
            case (.name, .text(let text)) where text != original.meal_name:
                changes.meal_name = text
            case (.calories, .whole(let number)) where number != original.calories:
                changes.calories = number
            case (.protein, .grams(let grams)) where grams != original.protein_g:
                changes.protein_g = grams
            case (.carbs, .grams(let grams)) where grams != original.carbohydrates_g:
                changes.carbohydrates_g = grams
            case (.fat, .grams(let grams)) where grams != original.fat_g:
                changes.fat_g = grams
            default:
                break
            }
        }
        return changes == MealChanges() ? nil : changes
    }

    // MARK: Parsing

    private enum Value: Equatable {
        case text(String), whole(Int), grams(Double)
    }

    private enum Problem: Error {
        case noName, controlCharacters, nameTooLong, notWhole, caloriesOutOfRange, notANumber, tooManyDecimals, gramsOutOfRange

        var message: String {
            switch self {
            case .noName: "Enter a name."
            case .controlCharacters: "Use letters, numbers and punctuation only."
            case .nameTooLong: "Use 80 characters or fewer."
            case .notWhole: "Enter a whole number."
            case .caloriesOutOfRange: "Enter 0 to 10,000 calories."
            case .notANumber: "Enter a number, like 12 or 12.5."
            case .tooManyDecimals: "Use at most one decimal."
            case .gramsOutOfRange: "Enter 0 to 1,000 g."
            }
        }
    }

    private func isEdited(_ field: Field) -> Bool {
        self[field] != MealForm(meal: original, locale: locale)[field]
    }

    private func parse(_ field: Field) -> Result<Value, Problem> {
        let text = self[field].trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .name:
            // As the server checks it: no control characters, something
            // visible, and at most 80 code points.
            let scalars = text.unicodeScalars
            if scalars.contains(where: { $0.properties.generalCategory == .control }) {
                return .failure(.controlCharacters)
            }
            if scalars.allSatisfy({ $0.properties.generalCategory == .format || $0.properties.isWhitespace }) {
                return .failure(.noName)
            }
            if scalars.count > 80 { return .failure(.nameTooLong) }
            return .success(.text(text))
        case .calories:
            guard let number = Int(text) else { return .failure(.notWhole) }
            guard (0...10_000).contains(number) else { return .failure(.caloriesOutOfRange) }
            return .success(.whole(number))
        case .protein, .carbs, .fat:
            // Digits (the device's own, or 0–9) with an optional decimal
            // part, in the device's format. A minus sign is never in range.
            let negative = text.hasPrefix("-")
            let parts = (negative ? String(text.dropFirst()) : text)
                .split(separator: locale.decimalSeparator ?? ".", omittingEmptySubsequences: false)
                .map { $0.map { $0.wholeNumberValue.map(String.init) ?? "?" }.joined() }
            guard (1...2).contains(parts.count),
                  parts.allSatisfy({ !$0.isEmpty && !$0.contains("?") }),
                  let grams = Double(parts.joined(separator: "."))
            else { return .failure(.notANumber) }
            guard !negative, (0...1_000).contains(grams) else { return .failure(.gramsOutOfRange) }
            if parts.count == 2, parts[1].count > 1 { return .failure(.tooManyDecimals) }
            return .success(.grams(grams))
        }
    }

    // MARK: Display

    /// Grams with at most one decimal and no trailing ".0": "18.5", "13", "0.3".
    static func gramsText(_ grams: Double, locale: Locale = .autoupdatingCurrent) -> String {
        grams.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...1)))
    }
}
