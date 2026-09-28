//
//  MealEditTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

private let base = URL(string: "http://Erics-Mac.local:8000")!
/// The store asks for today by the clock.
private let today = APIClient.dayString(.now, in: .autoupdatingCurrent)
private let pastDate = "2026-09-25"

/// The server's meals: id → calories, per date. Edits and deletes change it.
private final class Server: @unchecked Sendable {
    private let lock = NSLock()
    private var meals: [String: [Int: Int]]
    /// Holds day answers back while set, answering with the data from when
    /// the request arrived (a refresh that started before a change).
    var gate: DispatchSemaphore?

    init(_ meals: [String: [Int: Int]]) { self.meals = meals }

    func calories(_ id: Int, on date: String) -> Int? {
        lock.withLock { meals[date]?[id] }
    }

    func handle(_ request: URLRequest) throws -> (Int, Data) {
        let path = request.url?.path ?? ""
        if path.hasPrefix("/v1/days/") {
            let date = request.url!.lastPathComponent
            let snapshot = lock.withLock { meals[date] ?? [:] }
            if let gate { _ = gate.wait(timeout: .now() + 5) }
            return (200, Data(dayJSON(date, snapshot).utf8))
        }
        let id = Int(request.url!.lastPathComponent)!
        return try lock.withLock {
            guard let date = meals.first(where: { $0.value[id] != nil })?.key else {
                return (404, Data(#"{"error": {"code": "meal_not_found", "message": "Meal not found."}}"#.utf8))
            }
            if request.httpMethod == "DELETE" {
                meals[date]?[id] = nil
                return (204, Data())
            }
            guard let body = StubURLProtocol.bodyData(of: request) else { throw URLError(.badURL) }
            let changes = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            if let calories = changes["calories"] as? Int { meals[date]?[id] = calories }
            return (200, Data(mealJSON(id, calories: meals[date]![id]!, date: date, edited: true).utf8))
        }
    }
}

private func mealJSON(_ id: Int, calories: Int, date: String, edited: Bool = false) -> String {
    """
    {"id": \(id), "meal_name": "Meal \(id)", "calories": \(calories), "protein_g": 1.0,
     "carbohydrates_g": 1.0, "fat_g": 1.0, "confidence": 0.8, "calorie_low": 90,
     "calorie_high": 110, "assumptions": null, "source": null, "description": null,
     "local_date": "\(date)", "created_at": "\(date)T12:00:00Z",
     "edited_at": \(edited ? #""2026-09-27T14:05:00Z""# : "null")}
    """
}

private func dayJSON(_ date: String, _ meals: [Int: Int]) -> String {
    let total = meals.values.reduce(0, +)
    return """
    {"date": "\(date)", "goal": {"calories": 2200},
     "totals": {"calories": \(total), "protein_g": 1.0, "carbohydrates_g": 1.0, "fat_g": 1.0},
     "calories_remaining": \(max(2200 - total, 0)), "percentage": 0.0,
     "meals": [\(meals.keys.sorted().map { mealJSON($0, calories: meals[$0]!, date: date) }.joined(separator: ","))]}
    """
}

private func dayRequests(for date: String) -> Int {
    StubURLProtocol.requests.filter { $0.url?.path == "/v1/days/\(date)" }.count
}

/// Polls until `condition` holds (at most 2 s).
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

extension StubbedNetwork {
    /// Editing a meal: the saved meal shows at once, only its own day is
    /// fetched again, stale answers never undo it, and today and a past day
    /// stay apart.
    @Suite @MainActor struct MealEditTests {

        private func store(_ server: Server) -> NutritionStore {
            let store = NutritionStore(api: APIClient(baseURL: base, session: StubURLProtocol.session()))
            StubURLProtocol.handler = server.handle
            return store
        }

        /// Today and a past day loaded, as History has them.
        private func loaded(_ server: Server) async -> NutritionStore {
            let store = store(server)
            await store.refresh()
            await store.showDay(pastDate)
            return store
        }

        @Test func editingAPastMealUpdatesThatDayOnly() async throws {
            let server = Server([today: [1: 100], pastDate: [7: 300, 8: 200]])
            let store = await loaded(server)
            let todayRequests = dayRequests(for: today)
            let meal = try #require(store.pastDay?.meals.first { $0.id == 7 })

            let saved = try await store.updateMeal(meal, MealChanges(calories: 350))

            #expect(saved.calories == 350)
            #expect(saved.edited_at != nil)
            // Shown at once, before the day comes back.
            #expect(store.pastDay?.meals.first { $0.id == 7 }?.calories == 350)
            await waitUntil { store.pastDay?.totals.calories == 550 }
            #expect(store.pastDay?.totals.calories == 550)
            #expect(dayRequests(for: pastDate) == 2)
            #expect(dayRequests(for: today) == todayRequests)
            #expect(store.meals?.map(\.id) == [1])
            #expect(store.day?.totals.calories == 100)
        }

        @Test func editingTodaysMealUpdatesTheSharedToday() async throws {
            let server = Server([today: [1: 100, 2: 50], pastDate: [7: 300]])
            let store = await loaded(server)
            let meal = try #require(store.meals?.first { $0.id == 1 })

            _ = try await store.updateMeal(meal, MealChanges(calories: 400))

            #expect(store.meals?.first { $0.id == 1 }?.calories == 400)
            await waitUntil { store.day?.totals.calories == 450 }
            #expect(store.day?.totals.calories == 450)
            #expect(store.day?.calories_remaining == 1750)
            #expect(store.pastDay?.meals.map(\.id) == [7])
            #expect(dayRequests(for: pastDate) == 1)
        }

        /// A refresh of today that started before the edit must not put the
        /// old values back.
        @Test func aTodayRefreshFromBeforeTheEditIsDropped() async throws {
            let server = Server([today: [1: 100]])
            let store = store(server)
            await store.refresh()
            let meal = try #require(store.meals?.first)

            server.gate = DispatchSemaphore(value: 0)
            let older = Task { await store.refresh() }
            await waitUntil { dayRequests(for: today) == 2 }
            let gate = server.gate!
            server.gate = nil
            _ = try await store.updateMeal(meal, MealChanges(calories: 400))
            gate.signal()
            await older.value

            #expect(store.meals?.first?.calories == 400)
            await waitUntil { dayRequests(for: today) == 3 && !store.isRefreshing }
            #expect(store.meals?.first?.calories == 400)
            #expect(store.day?.totals.calories == 400)
        }

        /// The same for the past day.
        @Test func aPastDayLoadFromBeforeTheEditIsDropped() async throws {
            let server = Server([pastDate: [7: 300]])
            let store = store(server)
            await store.showDay(pastDate)
            let meal = try #require(store.pastDay?.meals.first)

            server.gate = DispatchSemaphore(value: 0)
            let older = Task { await store.refreshPastDay() }
            await waitUntil { dayRequests(for: pastDate) == 2 }
            let gate = server.gate!
            server.gate = nil
            _ = try await store.updateMeal(meal, MealChanges(calories: 350))
            gate.signal()
            await older.value

            #expect(store.pastDay?.meals.first?.calories == 350)
            await waitUntil { dayRequests(for: pastDate) == 3 && !store.isLoadingPastDay }
            #expect(store.pastDay?.meals.first?.calories == 350)
            #expect(store.pastDay?.totals.calories == 350)
        }

        @Test func aFailedEditChangesNothing() async throws {
            let server = Server([today: [1: 100], pastDate: [7: 300]])
            let store = await loaded(server)
            let requests = StubURLProtocol.requests.count
            let today = store.day
            let past = store.pastDay
            StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

            await #expect(throws: APIError.self) {
                try await store.updateMeal(past!.meals[0], MealChanges(calories: 1))
            }

            #expect(store.day?.meals.map(\.calories) == today?.meals.map(\.calories))
            #expect(store.pastDay?.meals.map(\.calories) == past?.meals.map(\.calories))
            #expect(store.loadError == nil)
            #expect(store.pastDayError == nil)
            #expect(StubURLProtocol.requests.count == requests + 1)
        }

        /// The meal was deleted elsewhere: its row goes, its day is fetched
        /// again, and the caller hears meal_not_found.
        @Test func editingADeletedMealRemovesItAndRefetchesItsDay() async throws {
            let server = Server([today: [1: 100], pastDate: [7: 300, 8: 200]])
            let store = await loaded(server)
            let meal = try #require(store.pastDay?.meals.first { $0.id == 7 })
            StubURLProtocol.handler = { request in
                request.httpMethod == "PATCH"
                    ? (404, Data(#"{"error": {"code": "meal_not_found", "message": "Meal not found."}}"#.utf8))
                    : try server.handle(request)
            }

            await #expect(throws: APIError.server(status: 404, code: "meal_not_found", message: "Meal not found.")) {
                try await store.updateMeal(meal, MealChanges(calories: 1))
            }

            #expect(store.pastDay?.meals.map(\.id) == [8])
            await waitUntil { dayRequests(for: pastDate) == 2 }
            #expect(dayRequests(for: pastDate) == 2)
            #expect(store.meals?.map(\.id) == [1])
        }

        /// An edit never puts a meal on another date.
        @Test func anEditNeverMovesAMealBetweenDates() async throws {
            let server = Server([today: [1: 100], pastDate: [7: 300]])
            let store = await loaded(server)
            let meal = try #require(store.pastDay?.meals.first)

            _ = try await store.updateMeal(meal, MealChanges(calories: 999))
            await waitUntil { dayRequests(for: pastDate) == 2 && !store.isLoadingPastDay }

            #expect(store.pastDay?.meals.map(\.id) == [7])
            #expect(store.meals?.map(\.id) == [1])
        }

        // MARK: Meal Detail's lookup

        @Test func lookupFindsTheMealOnItsLoadedDay() async throws {
            let server = Server([today: [1: 100], pastDate: [7: 300]])
            let store = await loaded(server)

            #expect(store.lookup(1, on: today) == .found(try #require(store.meals?.first)))
            #expect(store.lookup(7, on: pastDate) == .found(try #require(store.pastDay?.meals.first)))
        }

        /// Gone only when a loaded day for that date no longer has it.
        @Test func lookupSaysMissingOnlyForALoadedDay() async throws {
            let server = Server([today: [1: 100], pastDate: [7: 300]])
            let store = await loaded(server)

            #expect(store.lookup(8, on: pastDate) == .missing)
            #expect(store.lookup(1, on: "2026-09-20") == .notLoaded)

            store.selectDay("2026-09-24")
            #expect(store.lookup(7, on: pastDate) == .notLoaded)
        }
    }
}
