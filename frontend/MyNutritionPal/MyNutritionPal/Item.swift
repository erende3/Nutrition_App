//
//  Item.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 8/30/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
