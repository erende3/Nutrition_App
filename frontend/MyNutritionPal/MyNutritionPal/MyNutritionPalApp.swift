//
//  MyNutritionPalApp.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 8/30/26.
//

import SwiftUI

@main
struct MyNutritionPalApp: App {
    @State private var store = NutritionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
