//
//  OnboardingViewModel.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/1/26.
//


import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    // The input ranges, in one place. They are the app's existing ranges,
    // not nutrition policy; the backend's `ios-limits` test relies on them.
    static let ageRange = 13...120
    static let heightFeetRange = 3...8
    static let heightInchesRange = 0...11
    static let weightRangeLb = 70.0...700.0

    @Published var age: Int = 30
    @Published var sex: String = "male"
    @Published var heightFeet: Int = 5
    @Published var heightInches: Int = 9
    /// As typed. It's never rewritten; an invalid value is explained instead.
    @Published var weightText = "165"

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

    /// The typed weight in pounds, or nil if it isn't a number in range.
    var weightLb: Double? {
        // Double(String) accepts only a complete number, so "165lb" or "1 65"
        // is rejected instead of read as 165. The locale's decimal separator
        // (a comma in many regions) is swapped for "." first.
        let text = weightText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let pounds = Double(text),
              Self.weightRangeLb.contains(pounds)
        else {
            return nil
        }
        return pounds
    }

    var weightKg: Double? {
        weightLb.map { $0 * 0.45359237 }
    }

    var weightError: String? {
        weightLb == nil ? "Enter a weight between 70 and 700 lb." : nil
    }

    var inputsAreValid: Bool {
        Self.ageRange.contains(age)
            && Self.heightFeetRange.contains(heightFeet)
            && Self.heightInchesRange.contains(heightInches)
            && weightLb != nil
    }

    func submitOnboarding() async {
        // The steps already block invalid input; this is the backstop.
        guard inputsAreValid, let weightKg else {
            errorMessage = weightError ?? "Check your details and try again."
            return
        }

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
}
