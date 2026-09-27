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
    @Published var goalAdjusted = false

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Shown with the goal when the server used its default goal. The number
    /// is the returned goal.
    var goalAdjustedNotice: String? {
        guard goalAdjusted, let dailyCalorieGoal else {
            return nil
        }
        return "We couldn't calculate a calorie goal from these details, so we've used a default goal of \(dailyCalorieGoal.formatted()) calories per day."
    }

    /// BMR and maintenance are shown only when they're meaningful: positive,
    /// and the goal was calculated from them rather than replaced.
    var showsEnergyBreakdown: Bool {
        guard let bmr, let tdee else {
            return false
        }
        return !goalAdjusted && bmr > 0 && tdee > 0
    }

    var heightCm: Double {
        let totalInches = Double(heightFeet * 12 + heightInches)
        return totalInches * 2.54
    }

    var weightKg: Double {
        weightLb * 0.45359237
    }

    func submitOnboarding() async {
        validateInputs()
        isLoading = true
        errorMessage = nil

        do {
            let result = try await api.submitOnboarding(
                age: age,
                sex: sex,
                heightCm: heightCm,
                weightKg: weightKg,
                activityLevel: activityLevel,
                goal: goal
            )

            show(result)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
    func show(_ result: OnboardingResult) {
        bmr = result.bmr
        tdee = result.tdee
        dailyCalorieGoal = result.dailyCalorieGoal
        goalAdjusted = result.goalAdjusted
    }

    func validateInputs() {
        weightLb = min(max(weightLb, 70), 700)

        heightFeet = min(max(heightFeet, 3), 8)
        heightInches = min(max(heightInches, 0), 11)

        age = min(max(age, 13), 120)
    }
}
