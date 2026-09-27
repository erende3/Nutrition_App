//
//  ModelDecodingTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

/// The Swift models decode today's backend responses (shapes pinned by
/// backend/tests/test_contract.py), including fields the app doesn't model.
struct ModelDecodingTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func mealIgnoresFieldsTheAppDoesNotShow() throws {
        let meals = try decode([Meal].self, """
        [{"id": 7, "meal_name": "Chicken and rice", "calories": 650,
          "protein_g": 45.0, "carbohydrates_g": 70.0, "fat_g": 15.0,
          "confidence": 0.8, "calorie_low": 550, "calorie_high": 750,
          "created_at": "2026-09-25T16:04:05.123456"}]
        """)

        #expect(meals.count == 1)
        #expect(meals[0].id == 7)
        #expect(meals[0].calories == 650)
        #expect(meals[0].protein_g == 45.0)
        #expect(meals[0].created_at == "2026-09-25T16:04:05.123456")
    }

    @Test func mealWithWholeNumberMacrosDecodes() throws {
        let meals = try decode([Meal].self, """
        [{"id": 1, "meal_name": "Apple", "calories": 95, "protein_g": 0,
          "carbohydrates_g": 25, "fat_g": 0, "confidence": 1, "calorie_low": 80,
          "calorie_high": 110, "created_at": "2026-09-25T16:04:05"}]
        """)

        #expect(meals[0].carbohydrates_g == 25)
    }

    @Test(arguments: ["100", "100.0"])
    func dailySummaryPercentageDecodesAsIntOrFloat(_ percentage: String) throws {
        let summary = try decode(DailySummary.self, """
        {"date": "2026-09-25", "daily_goal": 2200, "calories_consumed": 2500,
         "calories_remaining": 0, "percentage": \(percentage)}
        """)

        #expect(summary.percentage == 100)
        #expect(summary.daily_goal == 2200)
        #expect(summary.calories_remaining == 0)
    }

    @Test func nutritionEstimateDecodes() throws {
        let estimate = try decode(NutritionEstimate.self, """
        {"meal_name": "Chicken and rice", "calories": 650, "protein_g": 45.0,
         "carbohydrates_g": 70.0, "fat_g": 15.0, "confidence": 0.8,
         "calorie_low": 550, "calorie_high": 750, "assumptions": ["1 cup rice"]}
        """)

        #expect(estimate.meal_name == "Chicken and rice")
        #expect(estimate.assumptions == ["1 cup rice"])
    }

    @Test func onboardingResultDecodesGoalAdjusted() throws {
        let result = try decode(OnboardingResult.self, """
        {"bmr": -779, "tdee": -935, "daily_calorie_goal": 2200, "goal_adjusted": true}
        """)

        #expect(result.dailyCalorieGoal == 2200)
        #expect(result.bmr == -779)
        #expect(result.goalAdjusted)
    }

    @Test func onboardingResultWithGoalAsCalculated() throws {
        let result = try decode(OnboardingResult.self, """
        {"bmr": 1649, "tdee": 2556, "daily_calorie_goal": 2556, "goal_adjusted": false}
        """)

        #expect(!result.goalAdjusted)
    }

    /// A server from before goal_adjusted existed still works.
    @Test func missingGoalAdjustedDecodesAsFalse() throws {
        let result = try decode(OnboardingResult.self, """
        {"bmr": 1649, "tdee": 2556, "daily_calorie_goal": 2556}
        """)

        #expect(!result.goalAdjusted)
        #expect(result.dailyCalorieGoal == 2556)
    }
}
