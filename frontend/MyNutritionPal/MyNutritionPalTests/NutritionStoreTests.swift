//
//  NutritionStoreTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

private let base = URL(string: "http://Erics-Mac.local:8000")!

private func mealJSON(_ id: Int, name: String = "Meal", calories: Int = 100, date: String = "2026-09-26") -> String {
    """
    {"id": \(id), "meal_name": "\(name) \(id)", "calories": \(calories), "protein_g": 1.0,
     "carbohydrates_g": 1.0, "fat_g": 1.0, "confidence": 0.8, "calorie_low": 90,
     "calorie_high": 110, "assumptions": [], "source": "text", "description": "x",
     "local_date": "\(date)", "created_at": "\(date)T12:00:00Z"}
    """
}

private func dayJSON(consumed: Int = 100, meals ids: [Int] = [1], date: String = "2026-09-26") -> String {
    """
    {"date": "\(date)", "goal": {"calories": 2200},
     "totals": {"calories": \(consumed), "protein_g": 1.0, "carbohydrates_g": 1.0, "fat_g": 1.0},
     "calories_remaining": \(max(2200 - consumed, 0)), "percentage": 0.0,
     "meals": [\(ids.map { mealJSON($0, date: date) }.joined(separator: ","))]}
    """
}

private let savedMealJSON = mealJSON(1, name: "Apple", calories: 95)

private func isDay(_ request: URLRequest) -> Bool {
    request.url?.path.hasPrefix("/v1/days/") == true
}

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

private var dayRequests: Int {
    StubURLProtocol.requests.filter(isDay).count
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

        /// Answers the day request; anything else gets `other`.
        private func respondToday(
            consumed: Int = 100,
            meals: [Int] = [1],
            status: Int = 200,
            other: @escaping (URLRequest) throws -> (Int, Data) = { _ in (200, Data("{}".utf8)) }
        ) {
            StubURLProtocol.handler = { request in
                isDay(request)
                    ? (status, Data(dayJSON(consumed: consumed, meals: meals).utf8))
                    : try other(request)
            }
        }

        @Test func startsEmpty() {
            let store = store()

            #expect(store.day == nil)
            #expect(store.meals == nil)
            #expect(store.loadError == nil)
            #expect(!store.isRefreshing)
        }

        @Test func refreshLoadsTodayInOneRequest() async {
            let store = store()
            respondToday(consumed: 650, meals: [7])

            await store.refresh()

            #expect(store.day?.totals.calories == 650)
            #expect(store.day?.goal.calories == 2200)
            #expect(store.meals?.map(\.id) == [7])
            #expect(store.loadError == nil)
            #expect(StubURLProtocol.requests.count == 1)
            #expect(StubURLProtocol.requests.first?.url?.path
                    == "/v1/days/\(APIClient.dayString(.now, in: .autoupdatingCurrent))")
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

            #expect(store.day?.totals.calories == 650)
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
            #expect(store.day != nil)
        }

        @Test func cancelledRefreshIsNotAnError() async {
            let store = store()
            StubURLProtocol.handler = { _ in throw URLError(.cancelled) }

            await store.refresh()

            #expect(store.loadError == nil)
            #expect(store.day == nil)
            #expect(!store.isRefreshing)
        }

        @Test func isRefreshingDuringLoad() async {
            let store = store()
            let gate = Gate()
            StubURLProtocol.handler = { _ in
                gate.wait()
                return (200, Data(dayJSON(consumed: 1).utf8))
            }

            let refresh = Task { await store.refresh() }
            await waitUntil { store.isRefreshing }
            #expect(store.isRefreshing)

            gate.open()
            await refresh.value
            #expect(!store.isRefreshing)
        }

        @Test func refreshWhileRefreshingSharesOneRequest() async {
            let store = store()
            let gate = Gate()
            StubURLProtocol.handler = { _ in
                gate.wait()
                return (200, Data(dayJSON(consumed: 1).utf8))
            }

            let first = Task { await store.refresh() }
            await waitUntil { StubURLProtocol.requests.count >= 1 }
            let second = Task { await store.refresh() }
            await Task.yield()

            gate.open()
            await first.value
            await second.value

            #expect(dayRequests == 1)
            #expect(store.day != nil)
        }

        @Test func logMealRefetchesAfterSaving() async throws {
            let store = store()
            let saved = Locked(false)
            StubURLProtocol.handler = { request in
                if request.url?.path == "/v1/meals/estimate" {
                    saved.set(true)
                    return (201, Data(savedMealJSON.utf8))
                }
                return (200, Data(dayJSON(consumed: saved.get() ? 95 : 0, meals: saved.get() ? [1] : []).utf8))
            }

            let meal = try await store.logMeal(message: "apple", imageData: nil)

            #expect(meal.meal_name == "Apple 1")
            #expect(StubURLProtocol.requests.first?.url?.path == "/v1/meals/estimate")
            await waitUntil { store.day?.totals.calories == 95 }
            #expect(store.day?.totals.calories == 95)
            #expect(store.meals?.map(\.id) == [1])
        }

        /// The meal is saved once the estimate returns, so the Dashboard shows
        /// it without waiting for the refresh (which could take 20 s or more
        /// on a bad network).
        @Test func logMealReturnsBeforeTheRefreshFinishes() async throws {
            let store = store()
            let gate = Gate()
            StubURLProtocol.handler = { request in
                if request.url?.path == "/v1/meals/estimate" {
                    return (201, Data(savedMealJSON.utf8))
                }
                gate.wait()
                return (200, Data(dayJSON(consumed: 95).utf8))
            }

            let meal = try await store.logMeal(message: "apple", imageData: nil)

            #expect(meal.calories == 95)
            #expect(store.day == nil)
            gate.open()
            await waitUntil { store.day != nil }
            #expect(store.day?.totals.calories == 95)
        }

        @Test func logMealFailureThrowsAndLeavesLoadErrorAlone() async {
            let store = store()
            respondToday { _ in (502, Data(#"{"error": {"code": "estimation_failed", "message": "Meal estimation failed. Please try again."}}"#.utf8)) }

            await #expect(throws: APIError.server(status: 502, code: "estimation_failed", message: "Meal estimation failed. Please try again.")) {
                _ = try await store.logMeal(message: "apple", imageData: nil)
            }
            #expect(store.loadError == nil)
            #expect(dayRequests == 0)
        }

        /// The meal was saved, so the caller gets it; the failed refresh
        /// shows only as the load error.
        @Test func logMealSuccessWithFailedRefreshReturnsTheMeal() async throws {
            let store = store()
            StubURLProtocol.handler = { request in
                request.url?.path == "/v1/meals/estimate"
                    ? (201, Data(savedMealJSON.utf8))
                    : (503, Data(#"{"error": {"code": "estimation_unavailable", "message": "Unavailable"}}"#.utf8))
            }

            let meal = try await store.logMeal(message: "apple", imageData: nil)

            #expect(meal.calories == 95)
            await waitUntil { store.loadError != nil }
            #expect(store.loadError != nil)
        }

        @Test func deleteRemovesRowAndRefetches() async throws {
            let store = store()
            let deleted = Locked(false)
            StubURLProtocol.handler = { request in
                if request.httpMethod == "DELETE" {
                    deleted.set(true)
                    return (204, Data())
                }
                return (200, Data(dayJSON(consumed: deleted.get() ? 100 : 200, meals: deleted.get() ? [8] : [7, 8]).utf8))
            }
            await store.refresh()
            let meal = try #require(store.meals?.first { $0.id == 7 })

            try await store.deleteMeal(meal)

            #expect(StubURLProtocol.requests.contains { $0.httpMethod == "DELETE" && $0.url?.path == "/v1/meals/7" })
            #expect(store.meals?.map(\.id) == [8])
            #expect(store.day?.totals.calories == 100)
            #expect(dayRequests == 2)
        }

        @Test func deleteFailureKeepsRowAndThrows() async throws {
            let store = store()
            respondToday(meals: [7]) { _ in (404, Data(#"{"error": {"code": "meal_not_found", "message": "Meal not found."}}"#.utf8)) }
            await store.refresh()
            let meal = try #require(store.meals?.first)

            await #expect(throws: APIError.server(status: 404, code: "meal_not_found", message: "Meal not found.")) {
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
                    return (204, Data())
                }
                // The held refresh answers with what the server had before the delete.
                let stale = holdNextRefresh.get() && !deleted.get()
                if stale { gate.wait() }
                let before = stale || !deleted.get()
                return (200, Data(dayJSON(consumed: before ? 200 : 100, meals: before ? [7, 8] : [8]).utf8))
            }
            await store.refresh()
            let meal = try #require(store.meals?.first { $0.id == 7 })

            holdNextRefresh.set(true)
            let olderRefresh = Task { await store.refresh() }
            await waitUntil { StubURLProtocol.requests.count >= 2 }
            let delete = Task { try await store.deleteMeal(meal) }
            await waitUntil { deleted.get() }
            await waitUntil { store.meals?.map(\.id) == [8] }
            #expect(store.meals?.map(\.id) == [8])

            gate.open()
            await olderRefresh.value
            #expect(store.meals?.contains { $0.id == 7 } == false)

            try await delete.value
            #expect(store.meals?.map(\.id) == [8])
            #expect(store.day?.totals.calories == 100)
        }
    }

    /// History's past day, beside today's shared state: loading any earlier
    /// date, latest selection wins, never another date's data, deletes, and
    /// what counts as today.
    @Suite @MainActor struct PastDayTests {

        private static let today = "2026-09-27"

        private func store(today: @escaping () -> String = { PastDayTests.today }) -> NutritionStore {
            NutritionStore(
                api: APIClient(baseURL: base, session: StubURLProtocol.session()),
                today: today
            )
        }

        /// The date a day request asks for.
        private static func date(of request: URLRequest) -> String? {
            guard isDay(request) else { return nil }
            return request.url?.lastPathComponent
        }

        /// Answers each day request with that date's meals from `meals`
        /// (ids), and anything else with `other`.
        private func respond(
            _ meals: [String: [Int]],
            status: Int = 200,
            other: @escaping (URLRequest) throws -> (Int, Data) = { _ in (204, Data()) }
        ) {
            StubURLProtocol.handler = { request in
                guard let date = Self.date(of: request) else { return try other(request) }
                let ids = meals[date] ?? []
                return (status, Data(dayJSON(consumed: 100 * ids.count, meals: ids, date: date).utf8))
            }
        }

        private func requests(for date: String) -> Int {
            StubURLProtocol.requests.filter { Self.date(of: $0) == date }.count
        }

        @Test func loadsThePastDayAskedFor() async {
            let store = store()
            respond(["2026-09-25": [7, 8]])

            await store.showDay("2026-09-25")

            #expect(store.pastDate == "2026-09-25")
            #expect(store.pastDay?.date == "2026-09-25")
            #expect(store.pastDay?.meals.map(\.id) == [7, 8])
            #expect(store.pastDay?.totals.calories == 200)
            #expect(store.pastDay?.goal.calories == 2200)
            #expect(store.pastDayError == nil)
            #expect(!store.isLoadingPastDay)
            #expect(requests(for: "2026-09-25") == 1)
        }

        @Test func aPastDayNeverChangesToday() async {
            let store = store()
            StubURLProtocol.handler = { request in
                let date = Self.date(of: request)!
                let ids = date == "2026-09-25" ? [7] : [1]
                return (200, Data(dayJSON(consumed: 100, meals: ids, date: date).utf8))
            }
            await store.refresh()
            let today = store.day?.date

            await store.showDay("2026-09-25")

            #expect(store.day?.date == today)
            #expect(store.meals?.map(\.id) == [1])
            #expect(store.pastDay?.meals.map(\.id) == [7])
        }

        @Test(arguments: [nil, "2026-09-27", "2026-09-28", "2027-01-01"])
        func todayOrLaterShowsToday(_ date: String?) async {
            let store = store()
            respond([:])

            await store.showDay(date)

            #expect(store.pastDate == nil)
            #expect(store.pastDay == nil)
            #expect(StubURLProtocol.requests.isEmpty)
        }

        @Test func switchingDaysClearsTheOldDayAtOnce() async {
            let store = store()
            respond(["2026-09-25": [7]])
            await store.showDay("2026-09-25")

            store.selectDay("2026-09-24")

            #expect(store.pastDate == "2026-09-24")
            #expect(store.pastDay == nil)
            #expect(store.pastDayError == nil)
        }

        /// A slow answer for an earlier choice must not replace the newer one.
        @Test func latestSelectionWins() async {
            let store = store()
            let gate = Gate()
            StubURLProtocol.handler = { request in
                let date = Self.date(of: request)!
                if date == "2026-09-24" { gate.wait() }
                return (200, Data(dayJSON(meals: date == "2026-09-24" ? [24] : [23], date: date).utf8))
            }

            let older = Task { await store.showDay("2026-09-24") }
            await waitUntil { requests(for: "2026-09-24") == 1 }
            await store.showDay("2026-09-23")
            gate.open()
            await older.value

            #expect(store.pastDate == "2026-09-23")
            #expect(store.pastDay?.date == "2026-09-23")
            #expect(store.pastDay?.meals.map(\.id) == [23])
            #expect(!store.isLoadingPastDay)
        }

        @Test func goingBackToTodayDropsAPastDayStillLoading() async {
            let store = store()
            let gate = Gate()
            StubURLProtocol.handler = { request in
                gate.wait()
                return (200, Data(dayJSON(meals: [7], date: Self.date(of: request)!).utf8))
            }

            let load = Task { await store.showDay("2026-09-25") }
            await waitUntil { StubURLProtocol.requests.count == 1 }
            await store.showDay(nil)
            gate.open()
            await load.value

            #expect(store.pastDate == nil)
            #expect(store.pastDay == nil)
            #expect(!store.isLoadingPastDay)
        }

        /// Switching to a day that fails to load shows the error, never the
        /// day shown before.
        @Test func aFailedNewDayShowsNoOtherDay() async {
            let store = store()
            respond(["2026-09-25": [7]])
            await store.showDay("2026-09-25")

            StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
            await store.showDay("2026-09-24")

            #expect(store.pastDate == "2026-09-24")
            #expect(store.pastDay == nil)
            #expect(store.pastDayError != nil)
            #expect(!store.isLoadingPastDay)
        }

        @Test func aFailedRefreshKeepsTheDayShown() async {
            let store = store()
            respond(["2026-09-25": [7]])
            await store.showDay("2026-09-25")

            respond([:], status: 503)
            await store.refreshPastDay()

            #expect(store.pastDay?.meals.map(\.id) == [7])
            #expect(store.pastDayError != nil)

            respond(["2026-09-25": [7]])
            await store.refreshPastDay()
            #expect(store.pastDayError == nil)
        }

        @Test func aCancelledLoadIsNotAnError() async {
            let store = store()
            StubURLProtocol.handler = { _ in throw URLError(.cancelled) }

            await store.showDay("2026-09-25")

            #expect(store.pastDayError == nil)
            #expect(!store.isLoadingPastDay)
        }

        @Test func deletingAPastMealRefreshesThatDayNotToday() async throws {
            let store = store()
            let deleted = Locked(false)
            StubURLProtocol.handler = { request in
                if request.httpMethod == "DELETE" {
                    deleted.set(true)
                    return (204, Data())
                }
                let date = Self.date(of: request)!
                let ids = date == "2026-09-25" ? (deleted.get() ? [8] : [7, 8]) : [1]
                return (200, Data(dayJSON(consumed: 100 * ids.count, meals: ids, date: date).utf8))
            }
            await store.refresh()
            let todayRequests = dayRequests
            await store.showDay("2026-09-25")
            let meal = try #require(store.pastDay?.meals.first { $0.id == 7 })

            try await store.deleteMeal(meal)

            #expect(StubURLProtocol.requests.contains { $0.httpMethod == "DELETE" && $0.url?.path == "/v1/meals/7" })
            #expect(store.pastDay?.meals.map(\.id) == [8])
            #expect(store.pastDay?.totals.calories == 100)
            #expect(requests(for: "2026-09-25") == 2)
            #expect(store.meals?.map(\.id) == [1])
            #expect(dayRequests - requests(for: "2026-09-25") == todayRequests)
        }

        /// Deleting today's meal (History on today) goes through today's
        /// shared state, so Today sees it; a past day chosen earlier is left alone.
        @Test func deletingTodaysMealUpdatesToday() async throws {
            let store = store()
            let deleted = Locked(false)
            StubURLProtocol.handler = { request in
                if request.httpMethod == "DELETE" {
                    deleted.set(true)
                    return (204, Data())
                }
                let date = Self.date(of: request)!
                let ids = date == "2026-09-25" ? [7] : (deleted.get() ? [2] : [1, 2])
                return (200, Data(dayJSON(consumed: 100 * ids.count, meals: ids, date: date).utf8))
            }
            await store.showDay("2026-09-25")
            await store.refresh()
            let meal = try #require(store.meals?.first { $0.id == 1 })

            try await store.deleteMeal(meal)

            #expect(store.meals?.map(\.id) == [2])
            #expect(store.day?.totals.calories == 100)
            #expect(store.pastDay?.meals.map(\.id) == [7])
            #expect(requests(for: "2026-09-25") == 1)
        }

        /// Coming back to the app refreshes today; the chosen past day stays.
        @Test func thePastDayOutlivesATodayRefresh() async {
            let store = store()
            StubURLProtocol.handler = { request in
                let date = Self.date(of: request)!
                return (200, Data(dayJSON(meals: [date == "2026-09-25" ? 7 : 1], date: date).utf8))
            }
            await store.showDay("2026-09-25")

            await store.refresh()

            #expect(store.pastDate == "2026-09-25")
            #expect(store.pastDay?.meals.map(\.id) == [7])
        }

        /// After midnight a chosen past day stays chosen; a timezone change
        /// that makes it today (or later) shows today instead.
        @Test func whatCountsAsTodayFollowsTheClock() async {
            let today = Locked(Self.today)
            let store = store(today: { today.get() })
            respond(["2026-09-26": [6]])
            await store.showDay("2026-09-26")

            today.set("2026-09-28")
            #expect(store.pastDate == "2026-09-26")

            today.set("2026-09-26")
            #expect(store.pastDate == nil)
        }
    }
}
