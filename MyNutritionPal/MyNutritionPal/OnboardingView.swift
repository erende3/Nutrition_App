import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var step = 0

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                progressIndicator

                Spacer()

                Group {
                    switch step {
                    case 0:
                        welcomeStep

                    case 1:
                        aboutStep

                    case 2:
                        bodyMetricsStep

                    case 3:
                        lifestyleStep

                    case 4:
                        resultsStep

                    default:
                        welcomeStep
                    }
                }

                Spacer()

                if step < 4 {
                    Button {
                        step += 1
                    } label: {
                        Text("Continue")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                } else if viewModel.dailyCalorieGoal == nil {
                    Button {
                        Task {
                            await viewModel.submitOnboarding()
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Calculate My Goal")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(viewModel.isLoading)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(24)
        }
        .foregroundStyle(.white)
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.blue : Color.gray.opacity(0.3))
                    .frame(height: 5)
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            Text("Welcome")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(
                "Let's personalize your nutrition plan and calculate a daily calorie goal."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
    }

    private var aboutStep: some View {
        VStack(spacing: 24) {
            Text("About You")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Age")
                    .fontWeight(.semibold)

                Stepper(
                    "\(viewModel.age) years old",
                    value: $viewModel.age,
                    in: 13...120
                )
                .padding()
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sex")
                    .fontWeight(.semibold)

                Picker("Sex", selection: $viewModel.sex) {
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var bodyMetricsStep: some View {
        VStack(spacing: 24) {
            Text("Body Metrics")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Height")
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Feet")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Stepper(
                            "\(viewModel.heightFeet) ft",
                            value: $viewModel.heightFeet,
                            in: 3...8
                        )
                        .padding()
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inches")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Stepper(
                            "\(viewModel.heightInches) in",
                            value: $viewModel.heightInches,
                            in: 0...11
                        )
                        .padding()
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Weight")
                    .fontWeight(.semibold)

                Stepper(
                    String(format: "%.1f lb", viewModel.weightLb),
                    value: $viewModel.weightLb,
                    in: 70...700,
                    step: 0.5
                )
                .padding()
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
    
    private var lifestyleStep: some View {
        VStack(spacing: 24) {
            Text("Lifestyle")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Activity Level")
                    .fontWeight(.semibold)

                Picker(
                    "Activity Level",
                    selection: $viewModel.activityLevel
                ) {
                    Text("Sedentary").tag("sedentary")
                    Text("Lightly Active").tag("lightly_active")
                    Text("Moderately Active").tag("moderately_active")
                    Text("Very Active").tag("very_active")
                    Text("Extremely Active").tag("extremely_active")
                }
                .pickerStyle(.menu)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Goal")
                    .fontWeight(.semibold)

                Picker(
                    "Goal",
                    selection: $viewModel.goal
                ) {
                    Text("Lose Weight").tag("lose_weight")
                    Text("Maintain Weight").tag("maintain")
                    Text("Gain Weight").tag("gain_weight")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var resultsStep: some View {
        VStack(spacing: 24) {
            Text("Your Plan")
                .font(.largeTitle)
                .fontWeight(.bold)

            if let dailyGoal = viewModel.dailyCalorieGoal {
                VStack(spacing: 8) {
                    Text("\(dailyGoal)")
                        .font(.system(size: 56, weight: .bold))

                    Text("calories per day")
                        .foregroundStyle(.secondary)
                }

                if let bmr = viewModel.bmr,
                   let tdee = viewModel.tdee {
                    HStack(spacing: 12) {
                        resultCard(
                            title: "BMR",
                            value: "\(bmr)"
                        )

                        resultCard(
                            title: "Maintenance",
                            value: "\(tdee)"
                        )
                    }
                }
            } else {
                Text(
                    "You're ready. Tap below to calculate your personalized calorie goal."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var cardBackground: Color {
        Color.white.opacity(0.08)
    }

    private func resultCard(
        title: String,
        value: String
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
