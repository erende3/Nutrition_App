//
//  CalorieRingTests.swift
//  MyNutritionPalTests
//

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
