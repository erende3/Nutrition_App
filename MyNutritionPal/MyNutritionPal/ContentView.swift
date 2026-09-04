import SwiftUI
import UIKit

struct DashboardView: View {
    @State private var mealText = ""
    @State private var lastResult: NutritionEstimate?

    @State private var dailyGoal = 2200
    @State private var caloriesConsumed = 0
    @State private var caloriesRemaining = 2200

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedImage: UIImage?
    @State private var showingCamera = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.08)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    VStack(alignment: .leading, spacing: 4) {
                        Text("TODAY")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.gray)

                        Text("Nutrition")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    CalorieRing(
                        consumed: Double(caloriesConsumed),
                        goal: Double(dailyGoal)
                    )

                    HStack(spacing: 12) {
                        StatCard(
                            title: "Consumed",
                            value: "\(caloriesConsumed)"
                        )

                        StatCard(
                            title: "Remaining",
                            value: "\(caloriesRemaining)"
                        )

                        StatCard(
                            title: "Goal",
                            value: "\(dailyGoal)"
                        )
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Log a meal")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)

                        TextField(
                            "What did you eat?",
                            text: $mealText,
                            axis: .vertical
                        )
                        .padding()
                        .foregroundStyle(.white)
                        .background(
                            Color.white.opacity(0.07)
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16)
                        )
                        
                        Button {
                            showingCamera = true
                        } label: {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Take Photo")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.10))
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16)
                        )
                        if let selectedImage {
                            VStack(spacing: 10) {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 180)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 16)
                                    )
                                    .clipped()
                                
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    
                                    Text("Photo ready to estimate")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    Button("Remove") {
                                        self.selectedImage = nil
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }

                        Button {
                            estimateMeal()
                        } label: {
                            HStack {
                                Spacer()

                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }

                                Text(
                                    isLoading
                                    ? "Estimating..."
                                    : "Estimate Meal"
                                )
                                .fontWeight(.semibold)

                                Spacer()
                            }
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(Color.blue)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16)
                        )
                        .disabled(
                            mealText
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                                && selectedImage == nil
                            || isLoading
                        )
                        .sheet(isPresented: $showingCamera) {
                            CameraPicker(image: $selectedImage)
                        }
                    }

                    if let lastResult {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Last meal added")
                                .font(.caption)
                                .foregroundStyle(.gray)

                            HStack {
                                VStack(alignment: .leading) {
                                    Text(lastResult.meal_name)
                                        .font(.headline)
                                        .foregroundStyle(.white)

                                    Text(
                                        "\(lastResult.calories) calories"
                                    )
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                        .background(
                            Color.white.opacity(0.06)
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 18)
                        )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    Spacer(minLength: 30)
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await refreshDailySummary()
        }
    }

    private func estimateMeal() {
        
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        let submittedMeal = mealText.trimmingCharacters(in: .whitespacesAndNewlines)

        let imageData = selectedImage?.jpegData(compressionQuality: 0.8)


        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await NutritionAPI.shared.estimateMeal(
                    message: submittedMeal.isEmpty
                        ? "Estimate this meal from the image."
                        : submittedMeal,
                    imageData: imageData
                )
                lastResult = result

                mealText = ""
                selectedImage = nil

                await refreshDailySummary()

            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    private func refreshDailySummary() async {
        do {
            let summary = try await NutritionAPI.shared
                .getDailySummary()

            dailyGoal = summary.daily_goal
            caloriesConsumed = summary.calories_consumed
            caloriesRemaining = summary.calories_remaining

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


struct CalorieRing: View {
    let consumed: Double
    let goal: Double

    var progress: Double {
        guard goal > 0 else {
            return 0
        }

        return min(consumed / goal, 1)
    }

    var remaining: Int {
        max(Int(goal - consumed), 0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.08),
                    lineWidth: 20
                )

            Circle()
                .trim(
                    from: 0,
                    to: progress
                )
                .stroke(
                    Color.blue,
                    style: StrokeStyle(
                        lineWidth: 20,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    .easeInOut(duration: 0.6),
                    value: progress
                )

            VStack(spacing: 4) {
                Text("\(remaining)")
                    .font(
                        .system(
                            size: 46,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.white)

                Text("calories left")
                    .foregroundStyle(.gray)
            }
        }
        .frame(
            maxWidth: .infinity
        )
        .frame(height: 260)
    }
}


struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.gray)

            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            Color.white.opacity(0.06)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 14)
        )
    }
}


struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }

            MealHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
        }
    }
}
