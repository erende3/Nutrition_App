//
//  MealHistoryView.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/3/26.
//


import SwiftUI

/// Today's meals from the shared store. Once meals have loaded, the list
/// stays on screen while refreshing and after a failed refresh.
struct MealHistoryView: View {
    @Environment(NutritionStore.self) private var store
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let meals = store.meals {
                    List {
                        if let loadError = store.loadError {
                            LoadErrorBanner(
                                title: "Couldn't update today's meals.",
                                message: loadError,
                                isRetrying: store.isRefreshing
                            ) {
                                Task { await store.refresh() }
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }

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
                    .overlay {
                        // Inside the list's space, so pull to refresh still works.
                        if meals.isEmpty {
                            ContentUnavailableView(
                                "No Meals Yet",
                                systemImage: "fork.knife",
                                description: Text("Your logged meals will appear here.")
                            )
                        }
                    }
                } else if let loadError = store.loadError {
                    ContentUnavailableView {
                        Label("Couldn't Load Meals", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button {
                            Task {
                                await store.refresh()
                            }
                        } label: {
                            if store.isRefreshing {
                                ProgressView()
                            } else {
                                Text("Retry")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isRefreshing)
                    }
                } else {
                    ProgressView("Loading meals...")
                }
            }
            .navigationTitle("Meal History")
            .refreshable {
                await store.refresh()
            }
            .alert(
                "Couldn't Delete Meal",
                isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func deleteMeal(_ meal: Meal) async {
        do {
            try await store.deleteMeal(meal)
        } catch where !APIError.isCancellation(error) {
            deleteError = error.localizedDescription
        } catch {}
    }
}
