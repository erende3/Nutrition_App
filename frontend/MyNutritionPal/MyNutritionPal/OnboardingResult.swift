//
//  OnboardingResult.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/1/26.
//


import Foundation

struct OnboardingResult: Codable {
    let bmr: Int
    let tdee: Int
    let dailyCalorieGoal: Int
    /// True when the calculation didn't give a usable (positive) goal and
    /// the server used its default instead.
    let goalAdjusted: Bool

    enum CodingKeys: String, CodingKey {
        case bmr
        case tdee
        case dailyCalorieGoal = "daily_calorie_goal"
        case goalAdjusted = "goal_adjusted"
    }
}

extension OnboardingResult {
    /// goal_adjusted is optional, so a server that doesn't send it still works.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bmr = try container.decode(Int.self, forKey: .bmr)
        tdee = try container.decode(Int.self, forKey: .tdee)
        dailyCalorieGoal = try container.decode(Int.self, forKey: .dailyCalorieGoal)
        goalAdjusted = try container.decodeIfPresent(Bool.self, forKey: .goalAdjusted) ?? false
    }
}
