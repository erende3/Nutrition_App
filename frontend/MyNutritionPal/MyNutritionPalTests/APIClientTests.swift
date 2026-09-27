//
//  APIClientTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

private let base = URL(string: "http://Erics-Mac.local:8000")!
private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

/// 2026-09-26 20:00 UTC: already 2026-09-27 in Tokyo.
private let lateEveningUTC = Date(timeIntervalSince1970: 1_790_452_800)

private let mealJSON = """
{"id": 7, "meal_name": "Chicken and rice", "calories": 650, "protein_g": 45.0,
 "carbohydrates_g": 70.0, "fat_g": 15.0, "confidence": 0.8, "calorie_low": 550,
 "calorie_high": 750, "assumptions": ["1 cup rice"], "source": "text",
 "description": "chicken and rice", "local_date": "2026-09-27",
 "created_at": "2026-09-27T16:04:05Z"}
"""
private let dayJSON = """
{"date": "2026-09-27", "goal": {"calories": 2633},
 "totals": {"calories": 650, "protein_g": 45.0, "carbohydrates_g": 70.0, "fat_g": 15.0},
 "calories_remaining": 1983, "percentage": 24.7, "meals": [\(mealJSON)]}
"""
private let profileJSON = """
{"id": 1, "age": null, "sex": null, "height_cm": null, "weight_kg": null,
 "activity_level": null, "goal": null, "daily_calorie_goal": 2200,
 "onboarding_complete": false}
"""
private let onboardingJSON = """
{"bmr": 1649, "tdee": 2556, "daily_calorie_goal": 2556, "goal_adjusted": false}
"""

extension StubbedNetwork {
    /// Every endpoint through a stubbed URLSession: method, path, headers,
    /// timeouts, body, decoding and error mapping.
    @Suite struct APIClientTests {

        private func client(baseURL: URL? = base) -> APIClient {
            APIClient(baseURL: baseURL, session: StubURLProtocol.session(), timeZone: { tokyo })
        }

        private func respond(_ json: String, status: Int = 200) {
            StubURLProtocol.handler = { _ in (status, Data(json.utf8)) }
        }

        private var onlyRequest: URLRequest {
            get throws {
                #expect(StubURLProtocol.requests.count == 1)
                return try #require(StubURLProtocol.requests.first)
            }
        }

        // MARK: - Endpoints

        @Test func day() async throws {
            let api = client()
            respond(dayJSON)

            let day = try await api.getDay(lateEveningUTC)

            #expect(day.totals.calories == 650)
            #expect(day.goal.calories == 2633)
            #expect(day.meals.map(\.id) == [7])
            #expect(try onlyRequest.httpMethod == "GET")
            #expect(try onlyRequest.url?.absoluteString == "http://Erics-Mac.local:8000/v1/days/2026-09-27")
        }

        /// A calendar date chosen in History is asked for exactly, in any timezone.
        @Test func dayForAChosenDate() async throws {
            let api = client()
            respond(dayJSON)

            _ = try await api.getDay("2026-09-25")

            #expect(try onlyRequest.httpMethod == "GET")
            #expect(try onlyRequest.url?.absoluteString == "http://Erics-Mac.local:8000/v1/days/2026-09-25")
        }

        /// The date asked for is the device's calendar date, not UTC's.
        @Test(arguments: [
            ("Asia/Tokyo", "2026-09-27"),
            ("UTC", "2026-09-26"),
            ("America/Los_Angeles", "2026-09-26"),
            ("Pacific/Kiritimati", "2026-09-27"),
        ])
        func dayIsTheDateInTheDeviceTimezone(_ zone: String, _ expected: String) {
            #expect(APIClient.dayString(lateEveningUTC, in: TimeZone(identifier: zone)!) == expected)
        }

        @Test func userProfile() async throws {
            let api = client()
            respond(profileJSON)

            let profile = try await api.getUserProfile()

            #expect(!profile.onboardingComplete)
            #expect(try onlyRequest.httpMethod == "GET")
            #expect(try onlyRequest.url?.absoluteString == "http://Erics-Mac.local:8000/v1/users/profile")
        }

        @Test func deleteMealAcceptsNoContent() async throws {
            let api = client()
            respond("", status: 204)

            try await api.deleteMeal(id: 7)

            #expect(try onlyRequest.httpMethod == "DELETE")
            #expect(try onlyRequest.url?.absoluteString == "http://Erics-Mac.local:8000/v1/meals/7")
        }

        @Test func submitOnboardingSendsTheSameJSON() async throws {
            let api = client()
            respond(onboardingJSON)

            let result = try await api.submitOnboarding(
                age: 30, sex: "male", heightCm: 175.26, weightKg: 74.8,
                activityLevel: "moderately_active", goal: "maintain"
            )

            #expect(result.dailyCalorieGoal == 2556)
            let request = try onlyRequest
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "http://Erics-Mac.local:8000/v1/users/onboarding")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

            let body = try #require(StubURLProtocol.bodyData(of: request))
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(json.keys) == ["age", "sex", "height_cm", "weight_kg", "activity_level", "goal"])
            #expect(json["age"] as? Int == 30)
            #expect(json["height_cm"] as? Double == 175.26)
            #expect(json["activity_level"] as? String == "moderately_active")
        }

        @Test func estimateMealSendsMultipartAndReturnsTheSavedMeal() async throws {
            let api = client()
            respond(mealJSON, status: 201)

            let meal = try await api.estimateMeal(message: "2 eggs", imageData: Data([0xFF, 0xD8]))

            #expect(meal.id == 7)
            #expect(meal.calories == 650)
            let request = try onlyRequest
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "http://Erics-Mac.local:8000/v1/meals/estimate")

            let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
            let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
            let body = try #require(StubURLProtocol.bodyData(of: request))
            #expect(body == APIClient.multipartBody(message: "2 eggs", imageData: Data([0xFF, 0xD8]), boundary: boundary))
        }

        // MARK: - Every request

        @Test func everyRequestSendsTheDeviceTimezone() async throws {
            let api = client()
            StubURLProtocol.handler = { request in
                switch request.url?.path {
                case "/v1/days/2026-09-27": (200, Data(dayJSON.utf8))
                case "/v1/users/profile": (200, Data(profileJSON.utf8))
                case "/v1/users/onboarding": (200, Data(onboardingJSON.utf8))
                case "/v1/meals/estimate": (201, Data(mealJSON.utf8))
                default: (204, Data())
                }
            }

            _ = try await api.getDay(lateEveningUTC)
            _ = try await api.getUserProfile()
            try await api.deleteMeal(id: 1)
            _ = try await api.submitOnboarding(
                age: 30, sex: "male", heightCm: 175, weightKg: 70,
                activityLevel: "sedentary", goal: "maintain"
            )
            _ = try await api.estimateMeal(message: "apple", imageData: nil)

            #expect(StubURLProtocol.requests.count == 5)
            for request in StubURLProtocol.requests {
                #expect(request.value(forHTTPHeaderField: "X-Timezone") == "Asia/Tokyo")
            }
        }

        @Test func timezoneIsReadForEachRequest() async throws {
            var zone = tokyo
            let api = APIClient(baseURL: base, session: StubURLProtocol.session(), timeZone: { zone })
            respond(dayJSON)

            _ = try await api.getDay(lateEveningUTC)
            zone = TimeZone(identifier: "Pacific/Kiritimati")!
            _ = try await api.getDay(lateEveningUTC)

            #expect(StubURLProtocol.requests.map { $0.value(forHTTPHeaderField: "X-Timezone") }
                    == ["Asia/Tokyo", "Pacific/Kiritimati"])
        }

        @Test func estimateWaits300SecondsAndOtherRequests20() async throws {
            let api = client()
            StubURLProtocol.handler = { request in
                request.url?.path == "/v1/meals/estimate"
                    ? (201, Data(mealJSON.utf8))
                    : (200, Data(dayJSON.utf8))
            }

            _ = try await api.estimateMeal(message: "apple", imageData: nil)
            _ = try await api.getDay(lateEveningUTC)

            #expect(StubURLProtocol.requests.map(\.timeoutInterval) == [300, 20])
        }

        // MARK: - Errors

        @Test func serverErrorCarriesTheBackendMessage() async {
            let api = client()
            respond(#"{"error": {"code": "estimation_unavailable", "message": "Meal estimation is not available right now."}}"#, status: 503)

            await #expect(throws: APIError.server(status: 503, code: "estimation_unavailable", message: "Meal estimation is not available right now.")) {
                _ = try await api.estimateMeal(message: "apple", imageData: nil)
            }
        }

        /// The backend's 413 text is what the user sees for an oversized photo.
        @Test func photoTooLargeShowsTheBackendMessage() async throws {
            let api = client()
            let message = "The photo is too large. Please choose a smaller photo."
            respond(#"{"error": {"code": "image_too_large", "message": "The photo is too large. Please choose a smaller photo."}}"#, status: 413)

            let error = await #expect(throws: APIError.self) {
                _ = try await api.estimateMeal(message: "lunch", imageData: Data([0xFF, 0xD8, 0xFF]))
            }
            #expect(error == .server(status: 413, code: "image_too_large", message: message))
            #expect(error?.localizedDescription == message)
        }

        @Test func notFoundOnDeleteIsAServerError() async {
            let api = client()
            respond(#"{"error": {"code": "meal_not_found", "message": "Meal not found."}}"#, status: 404)

            await #expect(throws: APIError.server(status: 404, code: "meal_not_found", message: "Meal not found.")) {
                try await api.deleteMeal(id: 999)
            }
        }

        @Test func connectionFailureIsATransportErrorNamingTheServer() async {
            let api = client()
            StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }

            do {
                _ = try await api.getUserProfile()
                Issue.record("expected an error")
            } catch let error as APIError {
                guard case .transport(let urlError, let server) = error else {
                    Issue.record("expected .transport, got \(error)")
                    return
                }
                #expect(urlError.code == .cannotConnectToHost)
                #expect(server == "Erics-Mac.local:8000")
            } catch {
                Issue.record("expected APIError, got \(error)")
            }
        }

        @Test func undecodableSuccessIsADecodingError() async {
            let api = client()
            respond(#"{"unexpected": true}"#)

            await #expect(throws: APIError.decoding) {
                _ = try await api.getDay(lateEveningUTC)
            }
        }

        @Test func noRetryAfterAFailure() async {
            let api = client()
            respond(#"{"error": {"code": "estimation_failed", "message": "Meal estimation failed. Please try again."}}"#, status: 502)

            _ = try? await api.estimateMeal(message: "apple", imageData: nil)

            #expect(StubURLProtocol.requests.count == 1)
        }

        @Test func missingBaseURLFailsWithoutARequest() async {
            let api = client(baseURL: nil)
            respond(dayJSON)

            await #expect(throws: APIError.notConfigured) {
                _ = try await api.getDay(lateEveningUTC)
            }
            #expect(StubURLProtocol.requests.isEmpty)
        }
    }
}
