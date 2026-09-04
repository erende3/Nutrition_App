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
    let created_at: String
}