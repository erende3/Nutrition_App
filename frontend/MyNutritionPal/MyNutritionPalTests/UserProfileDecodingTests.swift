//
//  UserProfileDecodingTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

/// RootView shows the Dashboard exactly when `onboardingComplete` is true,
/// so the backend's `onboarding_complete` must decode into it faithfully.
struct UserProfileDecodingTests {

    private func decode(_ json: String) throws -> UserProfile {
        try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
    }

    @Test func onboardedProfileDecodesAsComplete() throws {
        // Shape of GET /users/profile after onboarding.
        let profile = try decode("""
        {"id": 1, "age": 30, "sex": "male", "height_cm": 175.26,
         "weight_kg": 74.84274105, "activity_level": "moderately_active",
         "goal": "maintain", "daily_calorie_goal": 2633,
         "onboarding_complete": true}
        """)

        #expect(profile.onboardingComplete)
    }

    @Test func newProfileDecodesAsIncomplete() throws {
        // Shape of GET /users/profile before onboarding.
        let profile = try decode("""
        {"id": 1, "age": null, "sex": null, "height_cm": null,
         "weight_kg": null, "activity_level": null, "goal": null,
         "daily_calorie_goal": 2200, "onboarding_complete": false}
        """)

        #expect(!profile.onboardingComplete)
    }
}
