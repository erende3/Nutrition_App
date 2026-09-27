//
//  Day.swift
//  MyNutritionPal
//

import Foundation

/// One of the user's days (GET /v1/days/{date}): the meals logged on that
/// date, newest first, with their totals against the goal in effect that day.
struct Day: Codable {
    let date: String
    let goal: Goal
    let totals: Totals
    let calories_remaining: Int
    let percentage: Double
    var meals: [Meal]

    struct Goal: Codable {
        let calories: Int
    }

    struct Totals: Codable {
        let calories: Int
        let protein_g: Double
        let carbohydrates_g: Double
        let fat_g: Double
    }
}
