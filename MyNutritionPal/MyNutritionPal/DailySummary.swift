//
//  DailySummary.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 8/30/26.
//


import Foundation

struct DailySummary: Codable {
    let date: String
    let daily_goal: Int
    let calories_consumed: Int
    let calories_remaining: Int
    let percentage: Double
}