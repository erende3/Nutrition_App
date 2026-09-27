//
//  Meal.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/3/26.
//


import Foundation

struct Meal: Identifiable, Codable {
    let id: Int
    let meal_name: String
    let calories: Int
    let protein_g: Double
    let carbohydrates_g: Double
    let fat_g: Double
    /// The user's calendar date when the meal was logged (YYYY-MM-DD).
    let local_date: String
    let created_at: String
}