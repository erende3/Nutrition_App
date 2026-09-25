//
//  MealHistoryView.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/3/26.
//


import SwiftUI

struct MealHistoryView: View {
    @State private var meals: [Meal] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading meals...")
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding()
                } else if meals.isEmpty {
                    ContentUnavailableView(
                        "No Meals Yet",
                        systemImage: "fork.knife",
                        description: Text("Your logged meals will appear here.")
                    )
                } else {
                    List {
                        ForEach(meals) { meal in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(meal.meal_name)
                                    .font(.headline)

                                Text("\(meal.calories) calories")
                                    .font(.subheadline)

                                HStack(spacing: 12) {
                                    Text("P \(meal.protein_g, specifier: "%.0f")g")
                                    Text("C \(meal.carbohydrates_g, specifier: "%.0f")g")
                                    Text("F \(meal.fat_g, specifier: "%.0f")g")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        await deleteMeal(meal)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Meal History")
            .task {
                await loadMeals()
            }
            .refreshable {
                await loadMeals()
            }
        }
    }

    private func loadMeals() async {
        isLoading = true
        errorMessage = nil

        do {
            meals = try await NutritionAPI.shared.getTodaysMeals()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func deleteMeal(_ meal: Meal) async {
        do {
            try await NutritionAPI.shared.deleteMeal(id: meal.id)

            meals.removeAll {
                $0.id == meal.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
