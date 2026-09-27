//
//  OnboardingViewModelTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

private let base = URL(string: "http://Erics-Mac.local:8000")!

/// Unit conversion and the input ranges (the app's existing ranges; the
/// backend's `ios-limits` sweep test relies on them).
@MainActor
struct OnboardingInputTests {

    @Test func heightIsConvertedToCentimeters() {
        let model = OnboardingViewModel()
        model.heightFeet = 5
        model.heightInches = 9

        #expect(abs(model.heightCm - 175.26) < 0.0001)
    }

    @Test func weightIsConvertedToKilograms() throws {
        let model = OnboardingViewModel()
        model.weightText = "165"

        let kg = try #require(model.weightKg)
        #expect(abs(kg - 74.8427) < 0.0001)
    }

    @Test(arguments: ["70", "700", "165", "165.5", " 150 "])
    func weightInRangeIsAccepted(_ text: String) {
        let model = OnboardingViewModel()
        model.weightText = text

        #expect(model.weightError == nil)
        #expect(model.inputsAreValid)
    }

    /// Includes text a paste or hardware keyboard could enter: a number with
    /// anything else in it is rejected, not read as its leading digits.
    @Test(arguments: ["69.9", "700.1", "0", "-5", "", "abc", "1000", "165abc", "165lb", "1 65", "1,65"])
    func weightOutOfRangeIsRejectedVisibly(_ text: String) {
        let model = OnboardingViewModel()
        model.weightText = text

        #expect(model.weightError == "Enter a weight between 70 and 700 lb.")
        #expect(!model.inputsAreValid)
        #expect(model.weightKg == nil)
    }

    @Test func rangesMatchTheControls() {
        #expect(OnboardingViewModel.ageRange == 13...120)
        #expect(OnboardingViewModel.heightFeetRange == 3...8)
        #expect(OnboardingViewModel.heightInchesRange == 0...11)
        #expect(OnboardingViewModel.weightRangeLb == 70...700)
    }

    @Test func ageOutsideTheRangeIsInvalid() {
        let model = OnboardingViewModel()
        model.age = 12

        #expect(!model.inputsAreValid)
    }
}

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
            #expect(StubURLProtocol.requests.first?.url?.path == "/v1/users/onboarding")
        }

        /// The typed value is left as it is (not clamped) and nothing is sent.
        @Test func invalidWeightSendsNoRequest() async {
            let model = model()
            model.weightText = "40"
            StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }

            await model.submitOnboarding()

            #expect(StubURLProtocol.requests.isEmpty)
            #expect(model.weightText == "40")
            #expect(model.errorMessage == "Enter a weight between 70 and 700 lb.")
            #expect(model.dailyCalorieGoal == nil)
        }

        @Test func validInputSendsTheConvertedValues() async throws {
            let model = model()
            model.heightFeet = 5
            model.heightInches = 9
            model.weightText = "165"
            StubURLProtocol.handler = { _ in
                (200, Data(#"{"bmr": 1649, "tdee": 2556, "daily_calorie_goal": 2556, "goal_adjusted": false}"#.utf8))
            }

            await model.submitOnboarding()

            let request = try #require(StubURLProtocol.requests.first)
            let body = try #require(StubURLProtocol.bodyData(of: request))
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(abs((json["height_cm"] as? Double ?? 0) - 175.26) < 0.0001)
            #expect(abs((json["weight_kg"] as? Double ?? 0) - 74.8427) < 0.0001)
            #expect(model.dailyCalorieGoal == 2556)
        }

        @Test func serverErrorIsShown() async {
            let model = model()
            StubURLProtocol.handler = { _ in (503, Data(#"{"error": {"code": "estimation_unavailable", "message": "Try again later."}}"#.utf8)) }

            await model.submitOnboarding()

            #expect(model.errorMessage == "Try again later.")
            #expect(model.dailyCalorieGoal == nil)
            #expect(!model.isLoading)
        }
    }
}
