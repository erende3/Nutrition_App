//
//  UserProfile.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/1/26.
//

import Foundation

struct UserProfile: Codable {
    let id: Int
    let age: Int?
    let sex: String?
    let heightCm: Double?
    let weightKg: Double?
    let activityLevel: String?
    let goal: String?
    let dailyCalorieGoal: Int
    let onboardingComplete: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case age
        case sex
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case activityLevel = "activity_level"
        case goal
        case dailyCalorieGoal = "daily_calorie_goal"
        case onboardingComplete = "onboarding_complete"
    }
}
