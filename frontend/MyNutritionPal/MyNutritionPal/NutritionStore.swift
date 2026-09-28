//
//  NutritionStore.swift
//  MyNutritionPal
//

import Foundation
import Observation

/// Today (its totals, goal and meals), shared by the Today tab and History,
/// so both always show the same day. Only that shared server data lives here; form
/// text, photos and each action's own errors stay in their views.
///
/// History can also show one past day. It's kept apart from today: browsing
/// never changes `day`, and a past day is never today.
///
/// The server is the source of truth: logging or deleting a meal refetches
/// the day, and nothing is retried automatically (an estimate saves a meal).
@MainActor
@Observable
final class NutritionStore {
    /// nil until the first successful refresh.
    private(set) var day: Day?
    /// nil until the first successful refresh; empty on a day with no meals.
    var meals: [Meal]? { day?.meals }
    private(set) var isRefreshing = false
    /// Why the last refresh failed; cleared by the next successful one.
    private(set) var loadError: String?

    private let api: APIClient
    /// The refresh in flight. The store owns it, so a view that goes away
    /// stops waiting for it without cancelling the request.
    private var refreshTask: Task<Void, Never>?
    /// Bumped by every saved change, so a refresh that started before the
    /// change is dropped instead of showing old data.
    private var changes = 0

    // MARK: History's past day

    /// The past day History shows (YYYY-MM-DD), or nil when it shows today,
    /// and so follows midnight. Kept while the app runs. A date that is no
    /// longer in the past (after a timezone change) counts as today.
    var pastDate: String? {
        guard let selectedPastDate, selectedPastDate < today() else { return nil }
        return selectedPastDate
    }
    /// That day's data: nil while it first loads, or if that failed. Always
    /// the data of `pastDate`, never another day's.
    private(set) var pastDay: Day?
    private(set) var isLoadingPastDay = false
    /// Why the past day's last load failed; cleared by the next success.
    private(set) var pastDayError: String?

    private var selectedPastDate: String?
    /// Bumped by every past-day load and selection, so only the latest
    /// one's result is used.
    private var pastDayLoads = 0
    /// Today's date (YYYY-MM-DD), worked out each time it's needed.
    private let today: () -> String

    init(
        api: APIClient = .shared,
        today: @escaping () -> String = { APIClient.dayString(.now, in: .autoupdatingCurrent) }
    ) {
        self.api = api
        self.today = today
    }

    /// Loads today, in one request. "Today" is worked out on each refresh,
    /// so a refresh after midnight (or a timezone change) shows the new day.
    /// While a refresh is running, callers share it instead of starting
    /// another.
    func refresh() async {
        if refreshTask == nil {
            refreshTask = Task {
                await load()
                refreshTask = nil
            }
        }
        await refreshTask?.value
    }

    /// Estimates and saves a meal, and returns as soon as it's saved.
    /// Today's data is refetched in the background; if that fails, it shows
    /// as `loadError`, but the meal was still saved.
    /// `message` may be nil for a photo meal. Returns the saved meal.
    func logMeal(message: String?, imageData: Data?) async throws -> Meal {
        let meal = try await api.estimateMeal(message: message, imageData: imageData)
        refreshAfterChange()
        return meal
    }

    /// Deletes a meal on the server, removes its row at once, then refetches
    /// the day it was on: the past day History shows, or else today. If the
    /// delete fails, nothing changes and it throws.
    func deleteMeal(_ meal: Meal) async throws {
        try await api.deleteMeal(id: meal.id)
        if meal.local_date == pastDate {
            pastDay?.meals.removeAll { $0.id == meal.id }
            await refreshPastDay()
        } else {
            day?.meals.removeAll { $0.id == meal.id }
            await refreshAfterChange().value
        }
    }

    /// Saves an edit to a meal and returns the saved meal as soon as it's
    /// saved. The meal shows its new values at once; its own day (the past
    /// day History shows, or else today) is fetched again in the background
    /// for the totals, and any load of that day already running is dropped.
    /// If the meal no longer exists, its row goes, its day is fetched again,
    /// and it throws meal_not_found. Any other failure changes nothing.
    func updateMeal(_ meal: Meal, _ changes: MealChanges) async throws -> Meal {
        do {
            let saved = try await api.updateMeal(id: meal.id, changes)
            replace(meal.id, on: meal.local_date) { _ in saved }
            return saved
        } catch let error as APIError {
            if case .server(404, "meal_not_found"?, _) = error {
                replace(meal.id, on: meal.local_date) { _ in nil }
            }
            throw error
        }
    }

    /// What History has for a meal on its date: the meal, `missing` if that
    /// day is loaded without it (deleted), or `notLoaded` if no loaded day is
    /// that date (never read as deleted).
    func lookup(_ id: Meal.ID, on date: String) -> MealLookup {
        guard let loaded = [day, pastDay].compactMap({ $0 }).first(where: { $0.date == date }) else {
            return .notLoaded
        }
        return loaded.meals.first { $0.id == id }.map(MealLookup.found) ?? .missing
    }

    enum MealLookup: Equatable {
        case found(Meal)
        case missing
        case notLoaded
    }

    /// Replaces (or with nil removes) a meal's row on its day, then fetches
    /// that day again; a load of it already running is dropped first.
    private func replace(_ id: Meal.ID, on date: String, with newMeal: (Meal) -> Meal?) {
        func apply(_ meals: inout [Meal]) {
            meals = meals.compactMap { $0.id == id ? newMeal($0) : $0 }
        }

        if date == pastDate {
            pastDayLoads += 1
            if pastDay != nil { apply(&pastDay!.meals) }
            Task { await refreshPastDay() }
        } else {
            refreshAfterChange()
            if day != nil { apply(&day!.meals) }
        }
    }

    /// Shows `date` (YYYY-MM-DD) in History and loads it. Nil, today or a
    /// later date shows today.
    func showDay(_ date: String?) async {
        selectDay(date)
        await refreshPastDay()
    }

    /// Chooses the day History shows, at once. Another day's data is cleared
    /// straight away and any load still running is dropped, so nothing is
    /// ever shown under the wrong date. Call `refreshPastDay()` to load it.
    func selectDay(_ date: String?) {
        let date = date.flatMap { $0 < today() ? $0 : nil }
        guard date != selectedPastDate || date == nil else { return }
        selectedPastDate = date
        pastDayLoads += 1
        pastDay = nil
        pastDayError = nil
        isLoadingPastDay = false
    }

    /// Loads the past day again (nothing when History shows today). If it
    /// fails, the data already shown stays, with `pastDayError`.
    func refreshPastDay() async {
        guard let date = pastDate else { return }
        pastDayLoads += 1
        let load = pastDayLoads
        isLoadingPastDay = true
        defer {
            if load == pastDayLoads { isLoadingPastDay = false }
        }

        do {
            let newDay = try await api.getDay(date)

            guard load == pastDayLoads else { return }
            pastDay = newDay
            pastDayError = nil
        } catch {
            guard load == pastDayLoads, !APIError.isCancellation(error) else { return }
            pastDayError = error.localizedDescription
        }
    }

    /// Marks today's data as changed and fetches it again. A refresh already
    /// running may predate the change: it finishes (its result is dropped),
    /// then a new one starts.
    @discardableResult
    private func refreshAfterChange() -> Task<Void, Never> {
        changes += 1
        let olderRefresh = refreshTask
        return Task {
            await olderRefresh?.value
            await refresh()
        }
    }

    private func load() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let startedAt = changes

        do {
            let newDay = try await api.getDay(.now)

            guard startedAt == changes else { return }
            day = newDay
            loadError = nil
        } catch {
            guard startedAt == changes, !APIError.isCancellation(error) else { return }
            loadError = error.localizedDescription
        }
    }
}
