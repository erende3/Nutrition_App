//
//  OnboardingViewModelTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

private let base = URL(string: "http://Erics-Mac.local:8000")!

/// What the results step shows, from the onboarding response alone.
@MainActor
struct OnboardingResultDisplayTests {

    @Test func calculatedGoalShowsTheBreakdownAndNoNotice() {
        let model = OnboardingViewModel()
        model.show(OnboardingResult(bmr: 1649, tdee: 2556, dailyCalorieGoal: 2556, goalAdjusted: false))

        #expect(model.dailyCalorieGoal == 2556)
        #expect(model.showsEnergyBreakdown)
        #expect(model.goalAdjustedNotice == nil)
    }

    /// The notice names the goal the server returned, not a constant.
    @Test func adjustedGoalShowsTheNoticeWithTheReturnedGoal() {
        let model = OnboardingViewModel()
        model.show(OnboardingResult(bmr: 128, tdee: 154, dailyCalorieGoal: 2400, goalAdjusted: true))

        #expect(model.goalAdjustedNotice
                == "We couldn't calculate a calorie goal from these details, so we've used a default goal of \(2400.formatted()) calories per day.")
    }

    /// "2200 a day, Maintenance 154" would contradict itself.
    @Test func adjustedGoalHidesTheBreakdown() {
        let model = OnboardingViewModel()
        model.show(OnboardingResult(bmr: 128, tdee: 154, dailyCalorieGoal: 2200, goalAdjusted: true))

        #expect(!model.showsEnergyBreakdown)
    }

    @Test func nonPositiveEnergyIsNeverShown() {
        let model = OnboardingViewModel()
        model.show(OnboardingResult(bmr: -248, tdee: 1500, dailyCalorieGoal: 1500, goalAdjusted: false))
        #expect(!model.showsEnergyBreakdown)

        model.show(OnboardingResult(bmr: 1200, tdee: 0, dailyCalorieGoal: 1500, goalAdjusted: false))
        #expect(!model.showsEnergyBreakdown)
    }

    @Test func nothingIsShownBeforeTheResult() {
        let model = OnboardingViewModel()

        #expect(!model.showsEnergyBreakdown)
        #expect(model.goalAdjustedNotice == nil)
    }
}

extension StubbedNetwork {
    /// Submitting onboarding through a stubbed URLSession.
    @Suite @MainActor struct OnboardingSubmitTests {

        private func model() -> OnboardingViewModel {
            OnboardingViewModel(api: APIClient(baseURL: base, session: StubURLProtocol.session()))
        }

        @Test func submitShowsTheAdjustedResult() async {
            let model = model()
            StubURLProtocol.handler = { _ in
                (200, Data(#"{"bmr": 128, "tdee": 154, "daily_calorie_goal": 2200, "goal_adjusted": true}"#.utf8))
            }

            await model.submitOnboarding()

            #expect(model.dailyCalorieGoal == 2200)
            #expect(model.goalAdjustedNotice != nil)
            #expect(!model.showsEnergyBreakdown)
            #expect(StubURLProtocol.requests.first?.url?.path == "/users/onboarding")
        }

        @Test func serverErrorIsShown() async {
            let model = model()
            StubURLProtocol.handler = { _ in (503, Data(#"{"detail": "Try again later."}"#.utf8)) }

            await model.submitOnboarding()

            #expect(model.errorMessage == "Try again later.")
            #expect(model.dailyCalorieGoal == nil)
            #expect(!model.isLoading)
        }
    }
}
