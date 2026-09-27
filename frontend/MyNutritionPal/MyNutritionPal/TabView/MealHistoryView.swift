//
//  MealHistoryView.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/3/26.
//


import SwiftUI

/// One day's meals and totals: today (the shared day the Today tab shows)
/// or any earlier day. Once a day has loaded, its data stays on screen while
/// refreshing and after a failed refresh; another day's data never does.
struct MealHistoryView: View {
    @Environment(NutritionStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var deleteError: String?
    @State private var showingDatePicker = false

    // MARK: The day on screen

    private var isToday: Bool { store.pastDate == nil }
    private var todayDate: String {
        store.day?.date ?? APIClient.dayString(.now, in: .autoupdatingCurrent)
    }
    /// YYYY-MM-DD. Today's is the loaded day's, so the header always matches
    /// the meals under it.
    private var shownDate: String { store.pastDate ?? todayDate }
    private var shownDay: Day? { isToday ? store.day : store.pastDay }
    private var loadError: String? { isToday ? store.loadError : store.pastDayError }
    private var isLoading: Bool { isToday ? store.isRefreshing : store.isLoadingPastDay }
    private var title: String { Self.title(for: shownDate, today: todayDate) }

    /// Calories trail the name; at accessibility text sizes they go under
    /// it, so neither is squeezed.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    dateBar
                }
                .plainRow()

                if let day = shownDay {
                    if let loadError {
                        Section {
                            LoadErrorBanner(
                                title: isToday
                                    ? "Couldn't update today's meals."
                                    : "Couldn't update this day's meals.",
                                message: loadError,
                                isRetrying: isLoading
                            ) {
                                Task { await refresh() }
                            }
                            .padding(.horizontal)
                        }
                        .plainRow()
                    }

                    Section {
                        statCards(day)
                    }
                    .plainRow()

                    if !day.meals.isEmpty {
                        Section {
                            ForEach(day.meals) { meal in
                                mealRow(meal)
                            }
                        }
                    } else if loadError == nil {
                        // Not with a load error: the day may not really be empty.
                        Section {
                            emptyState
                        }
                        .plainRow()
                    }
                } else if let loadError {
                    // Nothing loaded for this day: no totals, just the error.
                    Section {
                        loadFailed(loadError)
                    }
                    .plainRow()
                } else {
                    Section {
                        statCards(nil)
                    }
                    .plainRow()

                    Section {
                        ProgressView(isToday ? "Loading meals..." : "Loading \(title)...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                    .plainRow()
                }
            }
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("History")
            .toolbar {
                if !isToday {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Today") {
                            go(to: nil)
                        }
                        .accessibilityLabel("Go to Today")
                        .accessibilityInputLabels(["Today", "Go to Today"])
                    }
                }
            }
            .refreshable {
                await refresh()
            }
            .sheet(isPresented: $showingDatePicker) {
                HistoryDatePicker(day: shownDate) { day in
                    // VoiceOver focus returns to the date, which reads it.
                    if day != shownDate { go(to: day, announce: false) }
                }
            }
            .alert(
                "Couldn't Delete Meal",
                isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    // MARK: Date bar

    /// Previous day, the date (which opens the calendar) and next day. At
    /// accessibility text sizes the date gets its own row.
    private var dateBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    dateButton

                    HStack {
                        stepButton(by: -1)
                        Spacer()
                        stepButton(by: 1)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    stepButton(by: -1)
                    dateButton
                    stepButton(by: 1)
                }
            }
        }
        .padding(6)
        .cardSurface()
        .padding(.horizontal)
    }

    private var dateButton: some View {
        Button {
            showingDatePicker = true
        } label: {
            // At accessibility sizes the icon goes above the date, so the
            // date gets the whole width.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 8))

            layout {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "Today" : title)
                        .font(.headline)
                        .foregroundStyle(.textPrimary)

                    if isToday {
                        Text(title)
                            .font(.footnote)
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 44,
                alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center
            )
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 10 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Date")
        .accessibilityValue(Self.spokenDate(for: shownDate, today: todayDate))
        .accessibilityHint("Opens a calendar. Swipe up or down to change the day.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            showingDatePicker = true
        }
        // VoiceOver reads the new value itself after an adjustment, so
        // these don't announce it again.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if !isToday { go(to: Self.shifted(shownDate, by: 1), announce: false) }
            case .decrement:
                go(to: Self.shifted(shownDate, by: -1), announce: false)
            @unknown default:
                break
            }
        }
    }

    /// Next is dimmed on today (and VoiceOver says so): there are no future days.
    private func stepButton(by days: Int) -> some View {
        let side: CGFloat = dynamicTypeSize.isAccessibilitySize ? 64 : 44

        return Button {
            go(to: Self.shifted(shownDate, by: days))
        } label: {
            Image(systemName: days < 0 ? "chevron.left" : "chevron.right")
                .font(.title3.weight(.semibold))
                .frame(minWidth: side, minHeight: side)
                .contentShape(Rectangle())
        }
        // Borderless: in a List row, buttons with the default style all
        // fire on a tap anywhere in the row.
        .buttonStyle(.borderless)
        .disabled(days > 0 && isToday)
        .accessibilityLabel(days < 0 ? "Previous day" : "Next day")
    }

    // MARK: Day content

    /// The day's totals against the goal in effect that day; dashes while
    /// the day first loads. Stacked at accessibility text sizes.
    private func statCards(_ day: Day?) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        let number = { (value: Int?) in value.map { $0.formatted() } ?? "–" }

        return layout {
            StatCard(title: "Consumed", value: number(day?.totals.calories))
            StatCard(title: "Remaining", value: number(day?.calories_remaining))
            StatCard(title: "Goal", value: number(day?.goal.calories))
        }
        .padding(.horizontal)
    }

    private func mealRow(_ meal: Meal) -> some View {
        rowLayout {
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.meal_name)
                    .font(.headline)
                    .foregroundStyle(.textPrimary)

                Text("P \(meal.protein_g, specifier: "%.0f")g · C \(meal.carbohydrates_g, specifier: "%.0f")g · F \(meal.fat_g, specifier: "%.0f")g")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(meal.calories.formatted()) cal")
                .font(.headline)
                .numeric()
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: meal))
        .listRowBackground(Color.surface)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    await deleteMeal(meal)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        Group {
            if isToday {
                ContentUnavailableView(
                    "No Meals Yet",
                    systemImage: "fork.knife",
                    description: Text("Your logged meals will appear here.")
                )
            } else {
                ContentUnavailableView(
                    "No Meals",
                    systemImage: "fork.knife",
                    description: Text("Nothing was logged on \(title).")
                )
            }
        }
    }

    private func loadFailed(_ message: String) -> some View {
        ContentUnavailableView {
            Label(
                isToday ? "Couldn't Load Meals" : "Couldn't Load \(title)",
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button {
                Task {
                    await refresh()
                }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Retry")
                }
            }
            .buttonStyle(PrimaryButtonStyle(minHeight: 44))
            .disabled(isLoading)
        }
    }

    // MARK: Actions

    /// Shows `date` (nil or today: today). With `announce`, VoiceOver says
    /// the new date, since the button that was used doesn't.
    private func go(to date: String?, announce: Bool = true) {
        store.selectDay(date)
        Task { await store.refreshPastDay() }

        if announce {
            // High priority, so it isn't cut off when the Today button
            // disappears and VoiceOver focus moves.
            var text = AttributedString(Self.spokenDate(for: shownDate, today: todayDate))
            text.accessibilitySpeechAnnouncementPriority = .high
            AccessibilityNotification.Announcement(text).post()
        }
    }

    private func refresh() async {
        if isToday {
            await store.refresh()
        } else {
            await store.refreshPastDay()
        }
    }

    private func deleteMeal(_ meal: Meal) async {
        do {
            try await store.deleteMeal(meal)
        } catch where !APIError.isCancellation(error) {
            deleteError = error.localizedDescription
        } catch {}
    }

    // MARK: Text

    /// One VoiceOver phrase per meal, with the units spelled out.
    static func accessibilityLabel(for meal: Meal) -> String {
        let grams = { (value: Double) in String(format: "%.0f", value) }
        return "\(meal.meal_name), \(meal.calories.formatted()) calories, "
            + "protein \(grams(meal.protein_g)) grams, "
            + "carbohydrates \(grams(meal.carbohydrates_g)) grams, "
            + "fat \(grams(meal.fat_g)) grams"
    }

    /// The start of a YYYY-MM-DD day in `calendar`'s timezone. The date is
    /// ISO (Gregorian) whatever calendar the device uses.
    static func date(_ day: String, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return gregorian(in: calendar.timeZone)
            .date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The calendar day `days` after `day` (before, if negative).
    static func shifted(_ day: String, by days: Int, calendar: Calendar = .autoupdatingCurrent) -> String {
        guard let start = date(day, calendar: calendar),
              let shifted = gregorian(in: calendar.timeZone).date(byAdding: .day, value: days, to: start)
        else { return day }
        return APIClient.dayString(shifted, in: calendar.timeZone)
    }

    private static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// "Friday, Sep 25", with the year when it isn't today's year.
    static func title(
        for day: String,
        today: String,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        guard let date = date(day, calendar: calendar) else { return day }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).month(.abbreviated).day()
        return day.prefix(4) == today.prefix(4)
            ? date.formatted(style)
            : date.formatted(style.year())
    }

    /// "Friday, September 25, 2026"; "Today, …" for today.
    static func spokenDate(
        for day: String,
        today: String,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        guard let date = date(day, calendar: calendar) else { return day }
        let spoken = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.wide).month(.wide).day().year()
        )
        return day == today ? "Today, \(spoken)" : spoken
    }
}

/// "Go to Date": the native calendar, up to today. Choosing a day or
/// changing the month only changes a draft; Done goes to the chosen day,
/// Cancel (or swiping the sheet away) leaves History where it was.
struct HistoryDatePicker: View {
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date

    /// Opens on `day` (YYYY-MM-DD), the day History shows.
    init(day: String, onDone: @escaping (String) -> Void) {
        _draft = State(initialValue: Self.draft(for: day))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker(
                    "Date",
                    selection: $draft,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
            }
            .navigationTitle("Go to Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(Self.day(of: draft))
                        dismiss()
                    }
                }
            }
        }
    }

    /// The calendar's starting selection for `day`: the start of that day,
    /// or now if it can't be read.
    static func draft(for day: String) -> Date {
        MealHistoryView.date(day) ?? .now
    }

    /// The day Done goes to (YYYY-MM-DD, in the device's timezone).
    static func day(of draft: Date) -> String {
        APIClient.dayString(draft, in: .autoupdatingCurrent)
    }
}

private extension View {
    /// A list row that is just its content: no inset, background or separator.
    func plainRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
