//
//  Meal.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/3/26.
//


import Foundation

struct Meal: Identifiable, Codable, Hashable {
    let id: Int
    let meal_name: String
    let calories: Int
    let protein_g: Double
    let carbohydrates_g: Double
    let fat_g: Double
    /// The AI's original estimate: its confidence (0–1) and calorie range.
    /// Editing the meal never changes these.
    let confidence: Double
    let calorie_low: Int
    let calorie_high: Int
    /// The AI's assumptions; nil for meals logged before they were kept.
    let assumptions: [String]?
    /// "text" or "photo"; nil when unknown (meals logged before it was kept).
    let source: String?
    /// The user's own text; nil when they gave none.
    let description: String?
    /// The user's calendar date when the meal was logged (YYYY-MM-DD).
    let local_date: String
    /// When it was logged, in UTC (YYYY-MM-DDTHH:MM:SSZ).
    let created_at: String
    /// When it was last edited (same format); nil if never.
    let edited_at: String?
}

/// An edit to a meal: only the fields set are sent (PATCH /v1/meals/{id}),
/// and each is saved exactly as given.
struct MealChanges: Encodable, Equatable {
    var meal_name: String?
    var calories: Int?
    var protein_g: Double?
    var carbohydrates_g: Double?
    var fat_g: Double?
}
