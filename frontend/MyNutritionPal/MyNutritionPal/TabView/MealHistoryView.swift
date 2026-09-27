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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var deleteError: String?

    /// Calories trail the name; at accessibility text sizes they go under
    /// it, so neither is squeezed.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
    }

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
                            rowLayout {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.meal_name)
                                        .font(.headline)
                                        .foregroundStyle(.textPrimary)

                                    Text("P \(meal.protein_g, specifier: "%.0f")g · C \(meal.carbohydrates_g, specifier: "%.0f")g · F \(meal.fat_g, specifier: "%.0f")g")
                                        .font(.footnote)
                                        .foregroundStyle(.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(meal.calories.formatted()) cal")
                                    .font(.headline)
                                    .numeric()
                                    .foregroundStyle(.textPrimary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Self.accessibilityLabel(for: meal))
                            .listRowBackground(Color.surface)
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
                    .scrollContentBackground(.hidden)
                    .overlay {
                        // Inside the list's space, so pull to refresh still works.
                        // Not with a load error: the day may not really be empty.
                        if meals.isEmpty && store.loadError == nil {
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
                        .buttonStyle(PrimaryButtonStyle(minHeight: 44))
                        .disabled(store.isRefreshing)
                    }
                } else {
                    ProgressView("Loading meals...")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
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

    /// One VoiceOver phrase per meal, with the units spelled out.
    static func accessibilityLabel(for meal: Meal) -> String {
        let grams = { (value: Double) in String(format: "%.0f", value) }
        return "\(meal.meal_name), \(meal.calories.formatted()) calories, "
            + "protein \(grams(meal.protein_g)) grams, "
            + "carbohydrates \(grams(meal.carbohydrates_g)) grams, "
            + "fat \(grams(meal.fat_g)) grams"
    }

    private func deleteMeal(_ meal: Meal) async {
        do {
            try await store.deleteMeal(meal)
        } catch where !APIError.isCancellation(error) {
            deleteError = error.localizedDescription
        } catch {}
    }
}
