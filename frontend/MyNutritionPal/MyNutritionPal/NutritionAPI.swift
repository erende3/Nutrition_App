//
//  NutritionAPI.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 8/30/26.
//


import Foundation

final class NutritionAPI {
    static let shared = NutritionAPI()

    private let baseURL = "http://172.20.10.9:8000"
    func estimateMeal(
        message: String,
        imageData: Data? = nil
    ) async throws -> NutritionEstimate {
        guard let url = URL(string: "\(baseURL)/meals/estimate") else {
            throw URLError(.badURL)
        }

        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300

        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        

        body.append(
            "Content-Disposition: form-data; name=\"message\"\r\n\r\n"
                .data(using: .utf8)!
        )

        body.append("\(message)\r\n".data(using: .utf8)!)
        
        if let imageData {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)

            body.append(
                "Content-Disposition: form-data; name=\"image\"; filename=\"meal.jpg\"\r\n"
                    .data(using: .utf8)!
            )

            body.append(
                "Content-Type: image/jpeg\r\n\r\n"
                    .data(using: .utf8)!
            )

            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(
            NutritionEstimate.self,
            from: data
        )
    }
    func getDailySummary() async throws -> DailySummary {
        guard let url = URL(string: "\(baseURL)/summary/daily") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(
            DailySummary.self,
            from: data
        )
    }
    
    func getTodaysMeals() async throws -> [Meal] {
        guard let url = URL(string: "\(baseURL)/meals/today") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([Meal].self, from: data)
    }
    func deleteMeal(id: Int) async throws {
        guard let url = URL(string: "\(baseURL)/meals/\(id)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
    
    func getUserProfile() async throws -> UserProfile {
        guard let url = URL(string: "\(baseURL)/users/profile") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(
            UserProfile.self,
            from: data
        )
    }
    func submitOnboarding(
        age: Int,
        sex: String,
        heightCm: Double,
        weightKg: Double,
        activityLevel: String,
        goal: String
    ) async throws -> OnboardingResult {

        guard let url = URL(string: "\(baseURL)/users/onboarding") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        let body: [String: Any] = [
            "age": age,
            "sex": sex,
            "height_cm": heightCm,
            "weight_kg": weightKg,
            "activity_level": activityLevel,
            "goal": goal
        ]

        request.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(
            OnboardingResult.self,
            from: data
        )
    }
}
