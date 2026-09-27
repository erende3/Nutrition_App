//
//  NutritionStore.swift
//  MyNutritionPal
//

import Foundation
import Observation

/// Today (its totals, goal and meals), shared by the Dashboard and History,
/// so both always show the same day. Only that shared server data lives here; form
/// text, photos and each action's own errors stay in their views.
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

    init(api: APIClient = .shared) {
        self.api = api
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
    /// today's data. If the delete fails, nothing changes and it throws.
    func deleteMeal(_ meal: Meal) async throws {
        try await api.deleteMeal(id: meal.id)
        day?.meals.removeAll { $0.id == meal.id }
        await refreshAfterChange().value
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
