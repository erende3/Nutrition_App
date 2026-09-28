//
//  AccessibilityTextTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

/// What VoiceOver reads for the Dashboard's calorie ring, after its
/// "Calories left" label.
struct CalorieRingTests {

    @Test func readsWhatIsLeftOfTheGoal() {
        #expect(
            CalorieRing.accessibilityValue(consumed: 1240, goal: 2633)
                == "\(1393.formatted()) of \(2633.formatted())"
        )
    }

    @Test func overTheGoalReadsNothingLeft() {
        #expect(
            CalorieRing.accessibilityValue(consumed: 3000, goal: 2633)
                == "0 of \(2633.formatted())"
        )
    }

    @Test func beforeTheFirstLoadSaysSo() {
        #expect(CalorieRing.accessibilityValue(consumed: nil, goal: nil) == "Not loaded yet")
    }
}

/// What VoiceOver reads for a meal in History.
struct MealRowAccessibilityTests {

    @Test func spellsOutTheUnits() throws {
        let meal = try JSONDecoder().decode(Meal.self, from: Data("""
        {"id": 1, "meal_name": "Chicken and rice", "calories": 650,
         "protein_g": 45.0, "carbohydrates_g": 70.4, "fat_g": 15.0,
         "confidence": 0.8, "calorie_low": 550, "calorie_high": 750,
         "local_date": "2026-09-27", "created_at": "2026-09-27T16:04:05Z"}
        """.utf8))

        #expect(
            MealHistoryView.accessibilityLabel(for: meal)
                == "Chicken and rice, \(650.formatted()) calories, protein 45 grams, "
                + "carbohydrates 70 grams, fat 15 grams"
        )
    }
}

/// The onboarding activity-level menu: the same options, in the same order,
/// and the chosen one's name as its label (and VoiceOver value).
struct ActivityLevelMenuTests {

    @Test func offersTheSameLevelsInOrder() {
        #expect(OnboardingView.activityLevels.map(\.tag) == [
            "sedentary", "lightly_active", "moderately_active", "very_active", "extremely_active",
        ])
        #expect(OnboardingView.activityLevels.map(\.title) == [
            "Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extremely Active",
        ])
    }

    @Test func labelNamesTheChosenLevel() {
        #expect(OnboardingView.activityLevelTitle("moderately_active") == "Moderately Active")
        #expect(OnboardingView.activityLevelTitle("sedentary") == "Sedentary")
    }

    @MainActor @Test func theDefaultLevelIsOffered() {
        #expect(OnboardingView.activityLevels.contains { $0.tag == OnboardingViewModel().activityLevel })
    }
}
