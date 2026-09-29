//
//  MealDetailView.swift
//  MyNutritionPal
//

import SwiftUI

/// One meal, opened from History: its numbers, when it was logged (and
/// edited), what it was logged from, and the AI's original estimate. Shows
/// only what the server has: sections without data are left out.
///
/// It follows the meal on its loaded day, so edits and refreshes show at
/// once. It says the meal is gone only when that day is loaded without it
/// (or a save finds it deleted), never because the day isn't loaded, and it
/// stays on screen rather than going back by itself.
struct MealDetailView: View {
    @Environment(NutritionStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var meal: Meal
    @State private var isGone = false
    @State private var isEditing = false

    init(meal: Meal) {
        _meal = State(initialValue: meal)
    }

    var body: some View {
        Group {
            if isGone {
                ContentUnavailableView(
                    "Meal Not Found",
                    systemImage: "fork.knife",
                    description: Text("It may have been deleted.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        numbers
                        origin
                        aiEstimate
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .navigationTitle("Meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isGone {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        isEditing = true
                    }
                    .accessibilityHint("Edits the name, calories and macros.")
                }
            }
        }
        .onChange(of: store.lookup(meal.id, on: meal.local_date), initial: true) { _, lookup in
            switch lookup {
            case .found(let current): meal = current
            case .missing: isGone = true
            case .notLoaded: break
            }
        }
        .sheet(isPresented: $isEditing) {
            EditMealView(meal: meal) { saved in
                meal = saved
            } onGone: {
                isGone = true
            }
        }
    }

    // MARK: Sections

    private var today: String { APIClient.dayString(.now, in: .autoupdatingCurrent) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meal.meal_name)
                .font(.title2.bold())
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(Self.loggedText(localDate: meal.local_date, createdAt: meal.created_at, today: today))
                .font(.subheadline)
                .foregroundStyle(.textSecondary)
                .accessibilityLabel(Self.spokenLogged(localDate: meal.local_date, createdAt: meal.created_at, today: today))

            if let edited = meal.edited_at.flatMap({ Self.editedText($0, today: today) }) {
                Label(edited, systemImage: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
                    .accessibilityLabel(meal.edited_at.flatMap { Self.editedText($0, today: today, spoken: true) } ?? edited)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardSurface()
    }

    private var numbers: some View {
        let macros = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { caloriesNumber; caloriesUnit }
                VStack(alignment: .leading, spacing: 0) { caloriesNumber; caloriesUnit }
            }

            Divider().overlay(Color.hairline)

            macros {
                macro("Protein", meal.protein_g)
                macro("Carbs", meal.carbohydrates_g)
                macro("Fat", meal.fat_g)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(meal.calories.formatted()) calories. "
                + "Protein \(MealForm.gramsText(meal.protein_g)) grams, "
                + "carbs \(MealForm.gramsText(meal.carbohydrates_g)) grams, "
                + "fat \(MealForm.gramsText(meal.fat_g)) grams."
        )
    }

    private var caloriesNumber: some View {
        Text(meal.calories.formatted())
            .font(.largeTitle.bold())
            .numeric()
            .foregroundStyle(.textPrimary)
    }

    private var caloriesUnit: some View {
        Text("cal")
            .font(.headline)
            .foregroundStyle(.textSecondary)
    }

    private func macro(_ name: String, _ grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.footnote)
                .foregroundStyle(.textSecondary)
            Text("\(MealForm.gramsText(grams)) g")
                .font(.title3.weight(.semibold))
                .numeric()
                .foregroundStyle(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where the meal came from; left out when nothing is known.
    @ViewBuilder private var origin: some View {
        let source = Self.sourceText(meal.source)
        if source != nil || meal.description != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let source {
                    row("Logged from", source)
                }
                if source != nil, meal.description != nil {
                    Divider().overlay(Color.hairline)
                }
                if let description = meal.description {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You wrote")
                            .font(.subheadline)
                            .foregroundStyle(.textSecondary)
                        Text("“\(description)”")
                            .foregroundStyle(.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .accessibilityElement(children: .combine)
                }
            }
            .cardSurface()
        }
    }

    /// Kept as the AI estimated it when the meal was logged (E6).
    private var aiEstimate: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Original AI estimate")
                .font(.footnote)
                .textCase(.uppercase)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 0) {
                row("Range", Self.rangeText(low: meal.calorie_low, high: meal.calorie_high))
                    .accessibilityLabel("Range, \(meal.calorie_low.formatted()) to \(meal.calorie_high.formatted()) calories")
                Divider().overlay(Color.hairline)
                row("Confidence", Self.confidenceText(meal.confidence))

                if let assumptions = meal.assumptions, !assumptions.isEmpty {
                    Divider().overlay(Color.hairline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Assumptions")
                            .font(.subheadline)
                            .foregroundStyle(.textSecondary)
                        ForEach(Array(assumptions.enumerated()), id: \.offset) { _, assumption in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").accessibilityHidden(true)
                                Text(assumption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .foregroundStyle(.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
            .cardSurface()

            Text("What the AI estimated when this meal was logged. Editing the meal doesn't change it.")
                .font(.footnote)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal)
        }
    }

    /// Label and value side by side; stacked at accessibility text sizes.
    private func row(_ label: String, _ value: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))

        return layout {
            Text(label)
                .foregroundStyle(.textSecondary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(value)
                .numeric()
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityElement(children: .combine)
    }

    // MARK: Text

    /// "Friday, Sep 25 · 8:50 PM": the day the meal counts toward, and the
    /// time it was logged in the phone's current timezone. (After travel the
    /// time can belong to another date; the logging timezone isn't stored.)
    static func loggedText(
        localDate: String,
        createdAt: String,
        today: String,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = timeZone
        let day = MealHistoryView.title(for: localDate, today: today, locale: locale, calendar: calendar)
        guard let logged = try? Date(createdAt, strategy: .iso8601) else { return day }
        return "\(day) · \(time(logged, locale: locale, timeZone: timeZone))"
    }

    /// For VoiceOver: "Logged Friday, September 25, 2026 at 8:50 PM".
    static func spokenLogged(
        localDate: String,
        createdAt: String,
        today: String,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = timeZone
        let day = MealHistoryView.spokenDate(for: localDate, today: today, locale: locale, calendar: calendar)
        guard let logged = try? Date(createdAt, strategy: .iso8601) else { return "Logged \(day)" }
        return "Logged \(day) at \(time(logged, locale: locale, timeZone: timeZone))"
    }

    /// "Edited Sep 28 at 2:05 PM", with the year when it isn't this year;
    /// `spoken` (for VoiceOver) writes the month in full.
    static func editedText(
        _ editedAt: String,
        today: String,
        spoken: Bool = false,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard let edited = try? Date(editedAt, strategy: .iso8601) else { return nil }
        var style = Date.FormatStyle(locale: locale, timeZone: timeZone).month(spoken ? .wide : .abbreviated).day()
        if APIClient.dayString(edited, in: timeZone).prefix(4) != today.prefix(4) {
            style = style.year()
        }
        return "Edited \(edited.formatted(style)) at \(time(edited, locale: locale, timeZone: timeZone))"
    }

    private static func time(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute())
    }

    /// "85%": the AI's own confidence, as a number (no thresholds).
    static func confidenceText(_ confidence: Double, locale: Locale = .autoupdatingCurrent) -> String {
        confidence.formatted(.percent.locale(locale).precision(.fractionLength(0)))
    }

    static func rangeText(low: Int, high: Int, locale: Locale = .autoupdatingCurrent) -> String {
        "\(low.formatted(.number.locale(locale)))–\(high.formatted(.number.locale(locale))) cal"
    }

    /// "Text" or "Photo"; nil when unknown, so the row is left out.
    static func sourceText(_ source: String?) -> String? {
        switch source {
        case "text": "Text"
        case "photo": "Photo"
        default: nil
        }
    }
}
