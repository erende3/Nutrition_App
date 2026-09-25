//
//  NutritionEstimate.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 8/30/26.
//


import Foundation

struct NutritionEstimate: Codable {
    let meal_name: String
    let calories: Int
    let protein_g: Double
    let carbohydrates_g: Double
    let fat_g: Double
    let confidence: Double
    let calorie_low: Int
    let calorie_high: Int
    let assumptions: [String]
}