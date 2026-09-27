//
//  NutritionStoreTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

private let base = URL(string: "http://Erics-Mac.local:8000")!

private func summaryJSON(consumed: Int) -> String {
    """
    {"date": "2026-09-26", "daily_goal": 2200, "calories_consumed": \(consumed),
     "calories_remaining": \(2200 - consumed), "percentage": 0.0}
    """
}

private func mealsJSON(_ ids: [Int]) -> String {
    let meals = ids.map { id in
        """
        {"id": \(id), "meal_name": "Meal \(id)", "calories": 100, "protein_g": 1.0,
         "carbohydrates_g": 1.0, "fat_g": 1.0, "confidence": 0.8, "calorie_low": 90,
         "calorie_high": 110, "created_at": "2026-09-26T12:00:00"}
        """
    }
    return "[" + meals.joined(separator: ",") + "]"
}

private let estimateJSON = """
{"meal_name": "Apple", "calories": 95, "protein_g": 0.5, "carbohydrates_g": 25.0,
 "fat_g": 0.3, "confidence": 0.9, "calorie_low": 80, "calorie_high": 110, "assumptions": []}
"""

/// Holds a stubbed response back until the test opens it. Waits at most 5 s,
/// so a broken test fails instead of hanging.
private final class Gate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func wait() { _ = semaphore.wait(timeout: .now() + 5) }
    func open() { semaphore.signal() }
}

/// A value shared with the stub handler, which runs on URLSession's thread.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}

private func requests(to path: String) -> Int {
    StubURLProtocol.requests.filter { $0.url?.path == path }.count
}

/// Polls until `condition` holds (at most 2 s).
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

extension StubbedNetwork {
    /// Today's shared state: refresh, coalescing, keeping data on failure,
    /// and fresh data after a meal is logged or deleted.
    @Suite @MainActor struct NutritionStoreTests {

        private func store() -> NutritionStore {
            NutritionStore(api: APIClient(baseURL: base, session: StubURLProtocol.session()))
        }

        /// Answers the two refresh requests; anything else gets `other`.
        private func respondToday(
            consumed: Int = 100,
            meals: [Int] = [1],
            status: Int = 200,
            other: @escaping (URLRequest) throws -> (Int, Data) = { _ in (200, Data("{}".utf8)) }
        ) {
            StubURLProtocol.handler = { request in
                switch request.url?.path {
                case "/summary/daily": (status, Data(summaryJSON(consumed: consumed).utf8))
                case "/meals/today": (status, Data(mealsJSON(meals).utf8))
                default: try other(request)
                }
            }
        }

        @Test func startsEmpty() {
            let store = store()

            #expect(store.summary == nil)
            #expect(store.meals == nil)
            #expect(store.loadError == nil)
            #expect(!store.isRefreshing)
        }

        @Test func refreshLoadsSummaryAndMeals() async {
            let store = store()
            respondToday(consumed: 650, meals: [7])

            await store.refresh()

            #expect(store.summary?.calories_consumed == 650)
            #expect(store.meals?.map(\.id) == [7])
            #expect(store.loadError == nil)
            #expect(requests(to: "/summary/daily") == 1)
            #expect(requests(to: "/meals/today") == 1)
        }

        @Test func emptyDayIsLoadedNotMissing() async {
            let store = store()
            respondToday(consumed: 0, meals: [])

            await store.refresh()

            #expect(store.meals?.isEmpty == true)
        }

        @Test func refreshFailureKeepsOldData() async {
            let store = store()
            respondToday(consumed: 650, meals: [7])
            await store.refresh()

            respondToday(status: 503)
            await store.refresh()

            #expect(store.summary?.calories_consumed == 650)
            #expect(store.meals?.map(\.id) == [7])
            #expect(store.loadError != nil)
        }

        @Test func partialFailureChangesNothing() async {
            let store = store()
            respondToday(consumed: 650, meals: [7])
            await store.refresh()

            StubURLProtocol.handler = { request in
                request.url?.path == "/summary/daily"
                    ? (200, Data(summaryJSON(consumed: 900).utf8))
                    : (500, Data(#"{"detail": "Internal Server Error"}"#.utf8))
            }
            await store.refresh()

            #expect(store.summary?.calories_consumed == 650)
            #expect(store.meals?.map(\.id) == [7])
            #expect(store.loadError != nil)
        }

        @Test func successClearsLoadError() async {
            let store = store()
            StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
            await store.refresh()
            #expect(store.loadError != nil)

            respondToday()
            await store.refresh()

            #expect(store.loadError == nil)
            #expect(store.summary != nil)
        }

        @Test func cancelledRefreshIsNotAnError() async {
            let store = store()
            StubURLProtocol.handler = { _ in throw URLError(.cancelled) }

            await store.refresh()

            #expect(store.loadError == nil)
            #expect(store.summary == nil)
            #expect(!store.isRefreshing)
        }

        @Test func isRefreshingDuringLoad() async {
            let store = store()
            let gate = Gate()
            StubURLProtocol.handler = { request in
                gate.wait()
                return request.url?.path == "/summary/daily"
                    ? (200, Data(summaryJSON(consumed: 1).utf8))
                    : (200, Data(mealsJSON([1]).utf8))
            }

            let refresh = Task { await store.refresh() }
            await waitUntil { store.isRefreshing }
            #expect(store.isRefreshing)

            gate.open()
            gate.open()
            await refresh.value
            #expect(!store.isRefreshing)
        }

        @Test func refreshWhileRefreshingSharesOneRequest() async {
            let store = store()
            let gate = Gate()
            StubURLProtocol.handler = { request in
                gate.wait()
                return request.url?.path == "/summary/daily"
                    ? (200, Data(summaryJSON(consumed: 1).utf8))
                    : (200, Data(mealsJSON([1]).utf8))
            }

            let first = Task { await store.refresh() }
            await waitUntil { StubURLProtocol.requests.count >= 1 }
            let second = Task { await store.refresh() }
            await Task.yield()

            gate.open()
            gate.open()
            await first.value
            await second.value

            #expect(requests(to: "/summary/daily") == 1)
            #expect(requests(to: "/meals/today") == 1)
            #expect(store.summary != nil)
        }

        @Test func logMealRefetchesAfterSaving() async throws {
            let store = store()
            let saved = Locked(false)
            StubURLProtocol.handler = { request in
                switch request.url?.path {
                case "/meals/estimate":
                    saved.set(true)
                    return (200, Data(estimateJSON.utf8))
                case "/summary/daily":
                    return (200, Data(summaryJSON(consumed: saved.get() ? 95 : 0).utf8))
                default:
                    return (200, Data(mealsJSON(saved.get() ? [1] : []).utf8))
                }
            }

            let estimate = try await store.logMeal(message: "apple", imageData: nil)

            #expect(estimate.meal_name == "Apple")
            #expect(StubURLProtocol.requests.first?.url?.path == "/meals/estimate")
            #expect(store.summary?.calories_consumed == 95)
            #expect(store.meals?.map(\.id) == [1])
        }

        @Test func logMealFailureThrowsAndLeavesLoadErrorAlone() async {
            let store = store()
            respondToday { _ in (502, Data(#"{"detail": "Meal estimation failed. Please try again."}"#.utf8)) }

            await #expect(throws: APIError.server(status: 502, message: "Meal estimation failed. Please try again.")) {
                _ = try await store.logMeal(message: "apple", imageData: nil)
            }
            #expect(store.loadError == nil)
            #expect(requests(to: "/summary/daily") == 0)
        }

        /// The meal was saved, so the caller gets the estimate; the failed
        /// refresh shows only as the load error.
        @Test func logMealSuccessWithFailedRefreshReturnsEstimate() async throws {
            let store = store()
            StubURLProtocol.handler = { request in
                request.url?.path == "/meals/estimate"
                    ? (200, Data(estimateJSON.utf8))
                    : (503, Data(#"{"detail": "Unavailable"}"#.utf8))
            }

            let estimate = try await store.logMeal(message: "apple", imageData: nil)

            #expect(estimate.calories == 95)
            #expect(store.loadError != nil)
        }

        @Test func deleteRemovesRowAndRefetches() async throws {
            let store = store()
            let deleted = Locked(false)
            StubURLProtocol.handler = { request in
                switch (request.httpMethod, request.url?.path) {
                case ("DELETE", _):
                    deleted.set(true)
                    return (200, Data(#"{"message": "Meal deleted.", "meal_id": 7}"#.utf8))
                case (_, "/summary/daily"):
                    return (200, Data(summaryJSON(consumed: deleted.get() ? 100 : 200).utf8))
                default:
                    return (200, Data(mealsJSON(deleted.get() ? [8] : [7, 8]).utf8))
                }
            }
            await store.refresh()
            let meal = try #require(store.meals?.first { $0.id == 7 })

            try await store.deleteMeal(meal)

            #expect(StubURLProtocol.requests.contains { $0.httpMethod == "DELETE" && $0.url?.path == "/meals/7" })
            #expect(store.meals?.map(\.id) == [8])
            #expect(store.summary?.calories_consumed == 100)
            #expect(requests(to: "/summary/daily") == 2)
        }

        @Test func deleteFailureKeepsRowAndThrows() async throws {
            let store = store()
            respondToday(meals: [7]) { _ in (404, Data(#"{"detail": "Meal not found."}"#.utf8)) }
            await store.refresh()
            let meal = try #require(store.meals?.first)

            await #expect(throws: APIError.server(status: 404, message: "Meal not found.")) {
                try await store.deleteMeal(meal)
            }
            #expect(store.meals?.map(\.id) == [7])
        }

        /// A refresh that started before the delete must not put the deleted
        /// meal back, and the store fetches again once the delete is done.
        @Test func refreshStartedBeforeDeleteDoesNotResurrectMeal() async throws {
            let store = store()
            let deleted = Locked(false)
            let gate = Gate()
            let holdNextRefresh = Locked(false)
            StubURLProtocol.handler = { request in
                if request.httpMethod == "DELETE" {
                    deleted.set(true)
                    return (200, Data(#"{"message": "Meal deleted.", "meal_id": 7}"#.utf8))
                }
                // The held refresh answers with what the server had before the delete.
                let stale = holdNextRefresh.get() && !deleted.get()
                if stale { gate.wait() }
                return request.url?.path == "/summary/daily"
                    ? (200, Data(summaryJSON(consumed: stale || !deleted.get() ? 200 : 100).utf8))
                    : (200, Data(mealsJSON(stale || !deleted.get() ? [7, 8] : [8]).utf8))
            }
            await store.refresh()
            let meal = try #require(store.meals?.first { $0.id == 7 })

            holdNextRefresh.set(true)
            let olderRefresh = Task { await store.refresh() }
            await waitUntil { StubURLProtocol.requests.count >= 3 }
            let delete = Task { try await store.deleteMeal(meal) }
            await waitUntil { deleted.get() }
            await waitUntil { store.meals?.map(\.id) == [8] }
            #expect(store.meals?.map(\.id) == [8])

            gate.open()
            gate.open()
            await olderRefresh.value
            #expect(store.meals?.contains { $0.id == 7 } == false)

            try await delete.value
            #expect(store.meals?.map(\.id) == [8])
            #expect(store.summary?.calories_consumed == 100)
        }
    }
}
