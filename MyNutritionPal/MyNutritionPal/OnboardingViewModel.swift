//
//  OnboardingViewModel.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/1/26.
//


import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var age: Int = 30
    @Published var sex: String = "male"
    @Published var heightFeet: Int = 5
    @Published var heightInches: Int = 9
    @Published var weightLb: Double = 165

    @Published var activityLevel: String = "moderately_active"
    @Published var goal: String = "maintain"

    @Published var bmr: Int?
    @Published var tdee: Int?
    @Published var dailyCalorieGoal: Int?

    @Published var isLoading = false
    @Published var errorMessage: String?
    
    var heightCm: Double {
        let totalInches = Double(heightFeet * 12 + heightInches)
        return totalInches * 2.54
    }

    var weightKg: Double {
        weightLb * 0.45359237
    }

    var onboardingComplete: Bool {
        dailyCalorieGoal != nil
    }

    func submitOnboarding() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await NutritionAPI.shared.submitOnboarding(
                age: age,
                sex: sex,
                heightCm: heightCm,
                weightKg: weightKg,
                activityLevel: activityLevel,
                goal: goal
            )

            bmr = result.bmr
            tdee = result.tdee
            dailyCalorieGoal = result.dailyCalorieGoal

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
