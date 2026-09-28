//
//  ModelDecodingTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

/// The Swift models decode the API v1 responses (shapes pinned by
/// backend/tests/test_v1_contract.py and test_v1_days.py), including fields
/// the app doesn't model.
struct ModelDecodingTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func mealIgnoresFieldsTheAppDoesNotShow() throws {
        let meals = try decode([Meal].self, """
        [{"id": 7, "meal_name": "Chicken and rice", "calories": 650,
          "protein_g": 45.0, "carbohydrates_g": 70.0, "fat_g": 15.0,
          "confidence": 0.8, "calorie_low": 550, "calorie_high": 750,
          "assumptions": ["1 cup rice"], "source": "photo", "description": null,
          "local_date": "2026-09-27", "created_at": "2026-09-27T16:04:05Z",
          "a_field_added_later": {"nested": true}}]
        """)

        #expect(meals.count == 1)
        #expect(meals[0].id == 7)
        #expect(meals[0].calories == 650)
        #expect(meals[0].protein_g == 45.0)
        #expect(meals[0].created_at == "2026-09-27T16:04:05Z")
        #expect(meals[0].local_date == "2026-09-27")
    }

    /// Meals logged before provenance was recorded have nulls.
    @Test func mealWithNullProvenanceDecodes() throws {
        let meals = try decode([Meal].self, """
        [{"id": 1, "meal_name": "Apple", "calories": 95, "protein_g": 0,
          "carbohydrates_g": 25, "fat_g": 0, "confidence": 1, "calorie_low": 80,
          "calorie_high": 110, "assumptions": null, "source": null,
          "description": null, "local_date": "2026-09-01",
          "created_at": "2026-09-01T16:04:05Z"}]
        """)

        #expect(meals[0].carbohydrates_g == 25)
    }

    /// What Meal Detail shows: the edit time and the AI's original estimate.
    @Test func mealDecodesTheDetailFields() throws {
        let meal = try decode(Meal.self, """
        {"id": 7, "meal_name": "Burrito bowl", "calories": 650, "protein_g": 42,
         "carbohydrates_g": 78, "fat_g": 24.5, "confidence": 0.7, "calorie_low": 600,
         "calorie_high": 850, "assumptions": ["A regular bowl"], "source": "text",
         "description": "burrito bowl", "local_date": "2026-09-28",
         "created_at": "2026-09-28T16:15:00Z", "edited_at": "2026-09-28T16:41:00Z"}
        """)

        #expect(meal.confidence == 0.7)
        #expect(meal.calorie_low == 600)
        #expect(meal.calorie_high == 850)
        #expect(meal.assumptions == ["A regular bowl"])
        #expect(meal.source == "text")
        #expect(meal.description == "burrito bowl")
        #expect(meal.edited_at == "2026-09-28T16:41:00Z")
    }

    /// A meal logged before 0.8 and never edited; also a server from before
    /// edited_at existed.
    @Test(arguments: [#""edited_at": null,"#, ""])
    func mealWithoutDetailsDecodesAsAbsent(_ editedAt: String) throws {
        let meal = try decode(Meal.self, """
        {"id": 16, "meal_name": "Pepperoni Pizza Slice", "calories": 280, "protein_g": 13,
         "carbohydrates_g": 30, "fat_g": 12, "confidence": 0.85, "calorie_low": 240,
         "calorie_high": 320, "assumptions": null, "source": null, "description": null,
         \(editedAt) "local_date": "2026-09-25", "created_at": "2026-09-26T03:50:37Z"}
        """)

        #expect(meal.assumptions == nil)
        #expect(meal.source == nil)
        #expect(meal.description == nil)
        #expect(meal.edited_at == nil)
        #expect(meal.confidence == 0.85)
    }

    @Test(arguments: ["100", "100.0"])
    func dayDecodesWithPercentageAsIntOrFloat(_ percentage: String) throws {
        let day = try decode(Day.self, """
        {"date": "2026-09-27", "goal": {"calories": 2200},
         "totals": {"calories": 2500, "protein_g": 80, "carbohydrates_g": 250.5, "fat_g": 70.1},
         "calories_remaining": 0, "percentage": \(percentage), "meals": [],
         "a_field_added_later": 1}
        """)

        #expect(day.percentage == 100)
        #expect(day.goal.calories == 2200)
        #expect(day.totals.calories == 2500)
        #expect(day.totals.carbohydrates_g == 250.5)
        #expect(day.calories_remaining == 0)
        #expect(day.meals.isEmpty)
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
