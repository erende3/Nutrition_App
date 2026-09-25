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

    enum CodingKeys: String, CodingKey {
        case bmr
        case tdee
        case dailyCalorieGoal = "daily_calorie_goal"
    }
}
