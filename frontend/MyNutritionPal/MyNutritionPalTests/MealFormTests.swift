//
//  MealFormTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

private let us = Locale(identifier: "en_US")

private func meal(protein: Double = 13, fat: Double = 12) throws -> Meal {
    try JSONDecoder().decode(Meal.self, from: Data("""
    {"id": 16, "meal_name": "Pepperoni Pizza Slice", "calories": 280, "protein_g": \(protein),
     "carbohydrates_g": 30, "fat_g": \(fat), "confidence": 0.85, "calorie_low": 240,
     "calorie_high": 320, "assumptions": null, "source": null, "description": null,
     "local_date": "2026-09-25", "created_at": "2026-09-26T03:50:37Z", "edited_at": null}
    """.utf8))
}

/// The Edit Meal form: prefill, validation messages, and what Save sends.
struct MealFormTests {

    @Test func opensWithTheMealsValuesAndNothingToSave() throws {
        let form = MealForm(meal: try meal(protein: 1.3, fat: 0.25), locale: us)

        #expect(form.name == "Pepperoni Pizza Slice")
        #expect(form.calories == "280")
        #expect(form.protein == "1.3")
        #expect(form.carbs == "30")
        #expect(!form.isDirty)
        #expect(form.isValid)
        #expect(form.changes == nil)
        #expect(MealForm.Field.allCases.allSatisfy { form.error(for: $0) == nil })
    }

    @Test func sendsOnlyWhatChanged() throws {
        var form = MealForm(meal: try meal(), locale: us)
        form.name = "  Two slices  "
        form.fat = "15.5"

        #expect(form.isDirty)
        #expect(form.changes == MealChanges(meal_name: "Two slices", fat_g: 15.5))
    }

    /// Calories and macros are independent: changing one leaves the others.
    @Test func changingCaloriesSendsNoMacros() throws {
        var form = MealForm(meal: try meal(), locale: us)
        form.calories = "320"

        #expect(form.changes == MealChanges(calories: 320))
    }

    /// Typing the same value back, or a different spelling of it, is no change.
    @Test func sameValuesAreNothingToSave() throws {
        var form = MealForm(meal: try meal(), locale: us)
        form.calories = "281"
        form.calories = "280"
        form.protein = "13.0"
        form.name = "Pepperoni Pizza Slice "

        #expect(form.changes == nil)
        #expect(form.isValid)
    }

    /// A stored value with more decimals than the form shows is never
    /// rounded by saving another field.
    @Test func anUntouchedPreciseValueIsNeverSent() throws {
        var form = MealForm(meal: try meal(fat: 0.123456), locale: us)
        #expect(form.fat == "0.1")
        form.calories = "300"

        #expect(form.changes == MealChanges(calories: 300))
    }

    @Test(arguments: [
        (MealForm.Field.name, "", "Enter a name."),
        (.name, "   ", "Enter a name."),
        (.name, String(repeating: "x", count: 81), "Use 80 characters or fewer."),
        (.calories, "", "Enter a whole number."),
        (.calories, "abc", "Enter a whole number."),
        (.calories, "2.5", "Enter a whole number."),
        (.calories, "10001", "Enter 0 to 10,000 calories."),
        (.calories, "-1", "Enter 0 to 10,000 calories."),
        (.protein, "", "Enter a number, like 12 or 12.5."),
        (.protein, "1..5", "Enter a number, like 12 or 12.5."),
        (.carbs, "abc", "Enter a number, like 12 or 12.5."),
        (.carbs, ".5", "Enter a number, like 12 or 12.5."),
        (.fat, "1000.5", "Enter 0 to 1,000 g."),
        (.fat, "-1", "Enter 0 to 1,000 g."),
        (.fat, "12.34", "Use at most one decimal."),
    ])
    func invalidInputIsExplainedAndBlocksSave(_ field: MealForm.Field, _ text: String, _ message: String) throws {
        var form = MealForm(meal: try meal(), locale: us)
        form[field] = text

        #expect(form.error(for: field) == message)
        #expect(!form.isValid)
        #expect(form.changes == nil)
        #expect(form.isDirty)
    }

    /// The server counts a name's code points: so does the form.
    @Test func nameLengthCountsLikeTheServer() throws {
        var form = MealForm(meal: try meal(), locale: us)
        form.name = String(repeating: "x", count: 79) + "👍🏽"
        #expect(form.error(for: .name) == "Use 80 characters or fewer.")

        form.name = String(repeating: "x", count: 78) + "👍🏽"
        #expect(form.error(for: .name) == nil)
    }

    @Test(arguments: [("\u{200B}", "Enter a name."), ("\u{200B} \u{200D}", "Enter a name."),
                      ("a\u{7}b", "Use letters, numbers and punctuation only.")])
    func invisibleOrControlCharactersAreRefused(_ name: String, _ message: String) throws {
        var form = MealForm(meal: try meal(), locale: us)
        form.name = name

        #expect(form.error(for: .name) == message)
    }

    @Test func minusZeroIsOutOfRange() throws {
        var form = MealForm(meal: try meal(), locale: us)
        form.fat = "-0"

        #expect(form.error(for: .fat) == "Enter 0 to 1,000 g.")
    }

    /// A locale with its own digits opens, and saves, in them.
    @Test func arabicDigitsWork() throws {
        let arabic = Locale(identifier: "ar_EG")
        var form = MealForm(meal: try meal(protein: 18.5), locale: arabic)
        #expect(form.isValid)

        form.protein = "٢٠٫٥"
        #expect(form.changes == MealChanges(protein_g: 20.5))
    }

    @Test func theLimitsThemselvesAreAccepted() throws {
        var form = MealForm(meal: try meal(), locale: us)
        form.name = String(repeating: "x", count: 80)
        form.calories = "0"
        form.protein = "1000"
        form.carbs = "0"
        form.fat = "999.9"

        #expect(form.isValid)
        #expect(form.changes == MealChanges(
            meal_name: String(repeating: "x", count: 80), calories: 0,
            protein_g: 1000, carbohydrates_g: 0, fat_g: 999.9
        ))
    }

    @Test func usesTheDevicesDecimalSeparator() throws {
        let german = Locale(identifier: "de_DE")
        var form = MealForm(meal: try meal(protein: 1.5), locale: german)
        #expect(form.protein == "1,5")

        form.protein = "2,5"
        #expect(form.changes == MealChanges(protein_g: 2.5))

        form.protein = "2.5"
        #expect(form.error(for: .protein) == "Enter a number, like 12 or 12.5.")
    }
}

/// How Meal Detail writes numbers, times and the edit time.
struct MealDetailTextTests {

    @Test(arguments: [(18.5, "18.5"), (13.0, "13"), (0.3, "0.3"), (0.25, "0.2"), (1000, "1000")])
    func gramsHaveAtMostOneDecimal(_ grams: Double, _ text: String) {
        #expect(MealForm.gramsText(grams, locale: us) == text)
    }

    @Test func confidenceIsAPercentage() {
        #expect(MealDetailView.confidenceText(0.85, locale: us) == "85%")
        #expect(MealDetailView.confidenceText(1, locale: us) == "100%")
    }

    @Test func rangeIsGrouped() {
        #expect(MealDetailView.rangeText(low: 1200, high: 1650, locale: us) == "1,200–1,650 cal")
    }

    @Test func loggedIsTheStoredDateWithTheTimeHere() {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        let text = MealDetailView.loggedText(
            localDate: "2026-09-25", createdAt: "2026-09-26T03:50:37Z",
            today: "2026-09-28", locale: us, timeZone: pacific
        )

        // iOS puts a narrow no-break space before AM/PM.
        #expect(text == "Friday, Sep 25 · 8:50\u{202F}PM")
    }

    @Test func editedHasTheDateAndTime() {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        let text = MealDetailView.editedText(
            "2026-09-28T21:05:00Z", today: "2026-09-28", locale: us, timeZone: pacific
        )

        #expect(text == "Edited Sep 28 at 2:05\u{202F}PM")
    }

    @Test func voiceOverHearsTheMonthInFull() {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!

        #expect(MealDetailView.spokenLogged(
            localDate: "2026-09-25", createdAt: "2026-09-26T03:50:37Z",
            today: "2026-09-28", locale: us, timeZone: pacific
        ) == "Logged Friday, September 25, 2026 at 8:50\u{202F}PM")
        #expect(MealDetailView.editedText(
            "2026-09-28T21:05:00Z", today: "2026-09-28", spoken: true, locale: us, timeZone: pacific
        ) == "Edited September 28 at 2:05\u{202F}PM")
    }

    @Test func editedInAnotherYearHasTheYear() {
        let text = MealDetailView.editedText(
            "2025-12-30T17:00:00Z", today: "2026-09-28", locale: us, timeZone: TimeZone(identifier: "UTC")!
        )

        #expect(text == "Edited Dec 30, 2025 at 5:00\u{202F}PM")
    }

    @Test func sourceIsNamedOnlyWhenKnown() {
        #expect(MealDetailView.sourceText("text") == "Text")
        #expect(MealDetailView.sourceText("photo") == "Photo")
        #expect(MealDetailView.sourceText(nil) == nil)
        #expect(MealDetailView.sourceText("voice") == nil)
    }
}
