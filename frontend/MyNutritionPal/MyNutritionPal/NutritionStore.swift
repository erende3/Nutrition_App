//
//  NutritionStore.swift
//  MyNutritionPal
//

import Foundation
import Observation

/// Today's summary and meals, shared by the Dashboard and History, so both
/// always show the same day. Only that shared server data lives here; form
/// text, photos and each action's own errors stay in their views.
///
/// The server is the source of truth: logging or deleting a meal refetches
/// both, and nothing is retried automatically (an estimate saves a meal).
@MainActor
@Observable
final class NutritionStore {
    /// nil until the first successful refresh.
    private(set) var summary: DailySummary?
    /// nil until the first successful refresh; empty on a day with no meals.
    private(set) var meals: [Meal]?
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

    /// Loads today's summary and meals together. While a refresh is running,
    /// callers share it instead of starting another.
    func refresh() async {
        if refreshTask == nil {
            refreshTask = Task {
                await load()
                refreshTask = nil
            }
        }
        await refreshTask?.value
    }

    /// Estimates and saves a meal, then refetches today's data. A failed
    /// refresh after the save shows as `loadError`; the meal was still saved,
    /// so the estimate is returned.
    func logMeal(message: String, imageData: Data?) async throws -> NutritionEstimate {
        let estimate = try await api.estimateMeal(message: message, imageData: imageData)
        await refreshAfterChange()
        return estimate
    }

    /// Deletes a meal on the server, removes its row at once, then refetches
    /// today's data. If the delete fails, nothing changes and it throws.
    func deleteMeal(_ meal: Meal) async throws {
        try await api.deleteMeal(id: meal.id)
        meals?.removeAll { $0.id == meal.id }
        await refreshAfterChange()
    }

    private func refreshAfterChange() async {
        changes += 1
        // A refresh already running may predate the change: let it finish
        // (its result is dropped), then fetch again.
        await refreshTask?.value
        await refresh()
    }

    private func load() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let startedAt = changes

        do {
            async let summary = api.getDailySummary()
            async let meals = api.getTodaysMeals()
            let (newSummary, newMeals) = try await (summary, meals)

            guard startedAt == changes else { return }
            self.summary = newSummary
            self.meals = newMeals
            loadError = nil
        } catch {
            guard startedAt == changes, !APIError.isCancellation(error) else { return }
            loadError = error.localizedDescription
        }
    }
}
