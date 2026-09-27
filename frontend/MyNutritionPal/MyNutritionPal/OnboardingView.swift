import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var step = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var welcomeIconSize: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var goalNumberSize: CGFloat = 56

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            // Scrolls only when a step doesn't fit (large text sizes);
            // otherwise the step stays centered as before.
            GeometryReader { geometry in
                ScrollView {
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
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            // Body Metrics can't continue with an invalid weight.
                            .disabled(step == 2 && viewModel.weightError != nil)
                        } else if viewModel.dailyCalorieGoal == nil {
                            Button {
                                Task {
                                    await viewModel.submitOnboarding()
                                }
                            } label: {
                                Group {
                                    if viewModel.isLoading {
                                        ProgressView()
                                    } else {
                                        Text("Calculate My Goal")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(viewModel.isLoading)
                        
                    } else {
                        Button {
                            onComplete()
                        } label: {
                            Text("Continue to Dashboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                        if let errorMessage = viewModel.errorMessage {
                            InlineError(message: errorMessage)
                        }
                    }
                    .padding(24)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(.textPrimary)
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.ring : Color.hairline)
                    .frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of 5")
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: welcomeIconSize))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Welcome")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(
                "Let's personalize your nutrition plan and calculate a daily calorie goal."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.textSecondary)
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
                    in: OnboardingViewModel.ageRange
                )
                .padding()
                .cardSurface()
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
                            .foregroundStyle(.textSecondary)

                        Stepper(
                            "\(viewModel.heightFeet) ft",
                            value: $viewModel.heightFeet,
                            in: OnboardingViewModel.heightFeetRange
                        )
                        .padding()
                        .cardSurface()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inches")
                            .font(.caption)
                            .foregroundStyle(.textSecondary)

                        Stepper(
                            "\(viewModel.heightInches) in",
                            value: $viewModel.heightInches,
                            in: OnboardingViewModel.heightInchesRange
                        )
                        .padding()
                        .cardSurface()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Weight")
                    .fontWeight(.semibold)

                HStack {
                    TextField("Weight", text: $viewModel.weightText)
                        .keyboardType(.decimalPad)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text("lb")
                        .foregroundStyle(.textSecondary)
                }
                .padding()
                .cardSurface()

                if let weightError = viewModel.weightError {
                    InlineError(message: weightError)
                }
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
                .cardSurface()
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
                    Text(dailyGoal.formatted())
                        .font(
                            .system(
                                size: goalNumberSize,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()

                    Text("calories per day")
                        .foregroundStyle(.textSecondary)
                }

                if let notice = viewModel.goalAdjustedNotice {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)

                        Text(notice)
                            .font(.footnote)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        .accentTint,
                        in: RoundedRectangle(cornerRadius: Radius.card)
                    )
                }

                if viewModel.showsEnergyBreakdown,
                   let bmr = viewModel.bmr,
                   let tdee = viewModel.tdee {
                    // Stacked at accessibility text sizes, so the numbers
                    // aren't broken across lines.
                    let cardLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 12))

                    cardLayout {
                        resultCard(
                            title: "BMR",
                            value: bmr.formatted()
                        )

                        resultCard(
                            title: "Maintenance",
                            value: tdee.formatted()
                        )
                    }
                }
            } else {
                Text(
                    "You're ready. Tap below to calculate your personalized calorie goal."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.textSecondary)
            }
        }
    }

    private func resultCard(
        title: String,
        value: String
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.textSecondary)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .numeric()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}
