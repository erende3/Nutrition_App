//
//  APIClient.swift
//  MyNutritionPal
//

import Foundation

/// The one way the app talks to the backend. Every request carries the
/// device's timezone (X-Timezone), so "today" is the user's local day.
/// Failures are thrown as `APIError`. Nothing is retried automatically: an
/// estimate saves the meal, so a retry could log it twice.
final class APIClient {
    static let shared = APIClient(baseURL: AppConfig.baseURL)

    static let defaultTimeout: TimeInterval = 20
    /// Above the backend's worst case (OPENAI_TIMEOUT_SECONDS × (retries + 1)).
    static let estimateTimeout: TimeInterval = 300

    private let baseURL: URL?
    private let session: URLSession
    private let timeZone: () -> TimeZone
    private let decoder = JSONDecoder()

    init(
        baseURL: URL?,
        session: URLSession = .shared,
        timeZone: @escaping () -> TimeZone = { .autoupdatingCurrent }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.timeZone = timeZone
    }

    // MARK: - Endpoints

    func estimateMeal(
        message: String,
        imageData: Data? = nil
    ) async throws -> NutritionEstimate {
        let boundary = UUID().uuidString

        return try await send(
            "POST",
            "/meals/estimate",
            body: Self.multipartBody(message: message, imageData: imageData, boundary: boundary),
            contentType: "multipart/form-data; boundary=\(boundary)",
            timeout: Self.estimateTimeout
        )
    }

    func getDailySummary() async throws -> DailySummary {
        try await send("GET", "/summary/daily")
    }

    func getTodaysMeals() async throws -> [Meal] {
        try await send("GET", "/meals/today")
    }

    func deleteMeal(id: Int) async throws {
        _ = try await data("DELETE", "/meals/\(id)")
    }

    func getUserProfile() async throws -> UserProfile {
        try await send("GET", "/users/profile")
    }

    func submitOnboarding(
        age: Int,
        sex: String,
        heightCm: Double,
        weightKg: Double,
        activityLevel: String,
        goal: String
    ) async throws -> OnboardingResult {
        let body: [String: Any] = [
            "age": age,
            "sex": sex,
            "height_cm": heightCm,
            "weight_kg": weightKg,
            "activity_level": activityLevel,
            "goal": goal
        ]

        return try await send(
            "POST",
            "/users/onboarding",
            body: try JSONSerialization.data(withJSONObject: body),
            contentType: "application/json"
        )
    }

    // MARK: - Requests

    static func multipartBody(message: String, imageData: Data?, boundary: String) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"message\"\r\n\r\n".utf8))
        body.append(Data("\(message)\r\n".utf8))

        if let imageData {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"meal.jpg\"\r\n".utf8))
            body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
            body.append(imageData)
            body.append(Data("\r\n".utf8))
        }

        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    private func send<T: Decodable>(
        _ method: String,
        _ path: String,
        body: Data? = nil,
        contentType: String? = nil,
        timeout: TimeInterval = defaultTimeout
    ) async throws -> T {
        let data = try await data(method, path, body: body, contentType: contentType, timeout: timeout)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func data(
        _ method: String,
        _ path: String,
        body: Data? = nil,
        contentType: String? = nil,
        timeout: TimeInterval = defaultTimeout
    ) async throws -> Data {
        guard let baseURL, let url = URL(string: baseURL.absoluteString + path) else {
            throw APIError.notConfigured
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(timeZone().identifier, forHTTPHeaderField: "X-Timezone")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.transport(error, server: Self.serverName(baseURL))
        }

        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw APIError.transport(URLError(.badServerResponse), server: Self.serverName(baseURL))
        }
        guard 200..<300 ~= status else {
            throw APIError.from(status: status, data: data)
        }
        return data
    }

    /// "host:port", for messages.
    private static func serverName(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return url.port.map { "\(host):\($0)" } ?? host
    }
}
