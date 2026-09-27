import PhotosUI
import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(NutritionStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var mealText = ""
    @State private var lastResult: Meal?

    @State private var isLoading = false
    @State private var estimateError: String?
    @State private var photo = PhotoDraft()
    @State private var cameraImage: UIImage?
    @State private var showingCamera = false
    @State private var libraryItem: PhotosPickerItem?
    // Presenting the camera picker without an available camera raises an exception.
    private let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
    @FocusState private var isMealFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("TODAY")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .tracking(0.8)
                                .foregroundStyle(.textSecondary)

                            // Only before the first load; later refreshes keep the numbers.
                            if store.day == nil && store.isRefreshing {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }

                        Text("Nutrition")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.textPrimary)
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()

                            Button("Done") {
                                isMealFieldFocused = false
                            }
                        }
                    }

                    if let loadError = store.loadError {
                        LoadErrorBanner(
                            title: "Couldn't update today's totals.",
                            message: loadError,
                            isRetrying: store.isRefreshing
                        ) {
                            Task { await store.refresh() }
                        }
                    }

                    CalorieRing(
                        consumed: store.day?.totals.calories,
                        goal: store.day?.goal.calories
                    )

                    // Stacked at accessibility text sizes, so the numbers
                    // aren't squeezed.
                    let statLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 12))

                    statLayout {
                        StatCard(
                            title: "Consumed",
                            value: Self.number(store.day?.totals.calories)
                        )

                        StatCard(
                            title: "Remaining",
                            value: Self.number(store.day?.calories_remaining)
                        )

                        StatCard(
                            title: "Goal",
                            value: Self.number(store.day?.goal.calories)
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Log a meal")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.textPrimary)

                        TextField(
                            "What did you eat?",
                            text: $mealText,
                            prompt: Text("What did you eat?")
                                .foregroundStyle(.textSecondary),
                            axis: .vertical
                        )
                        .focused($isMealFieldFocused)
                        .padding()
                        .foregroundStyle(.textPrimary)
                        .background(
                            .fieldFill,
                            in: RoundedRectangle(cornerRadius: Radius.control)
                        )

                        HStack(spacing: 12) {
                            if hasCamera {
                                Button {
                                    showingCamera = true
                                } label: {
                                    photoSourceLabel("Take Photo", systemImage: "camera.fill")
                                }
                            }

                            PhotosPicker(selection: $libraryItem, matching: .images) {
                                photoSourceLabel("Choose Photo", systemImage: "photo.on.rectangle")
                            }
                        }
                        .buttonStyle(.plain)
                        if photo.isPreparing {
                            HStack {
                                ProgressView()
                                Text("Preparing photo...")
                                    .font(.subheadline)
                                    .foregroundStyle(.textSecondary)

                                Spacer()

                                // A slow library photo (e.g. downloading from
                                // iCloud) would otherwise block Estimate.
                                Button("Cancel") {
                                    photo.cancel()
                                }
                                .font(.subheadline)
                            }
                        } else if let prepared = photo.photo {
                            VStack(spacing: 10) {
                                Image(uiImage: prepared.preview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 180)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: Radius.control)
                                    )
                                    .clipped()

                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)

                                    Text("Photo ready to estimate")
                                        .font(.subheadline)
                                        .foregroundStyle(.textSecondary)

                                    Spacer()

                                    Button("Remove") {
                                        photo.remove()
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }

                        Button {
                            estimateMeal()
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                }

                                Text(
                                    isLoading
                                    ? "Estimating..."
                                    : "Estimate Meal"
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(
                            mealText
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                                && photo.photo == nil
                            || isLoading
                            || photo.isPreparing
                        )
                        .sheet(isPresented: $showingCamera) {
                            CameraPicker(image: $cameraImage)
                        }
                        .onChange(of: cameraImage) { _, image in
                            guard let image else { return }
                            cameraImage = nil
                            photo.prepare { image }
                        }
                        .onChange(of: libraryItem) { _, item in
                            guard let item else { return }
                            // Cleared so picking the same photo again still triggers.
                            libraryItem = nil
                            photo.prepare {
                                guard let data = try? await item.loadTransferable(type: Data.self) else {
                                    return nil
                                }
                                return UIImage(data: data)
                            }
                        }

                        if let photoError = photo.error {
                            InlineError(message: photoError)
                        }

                        if let estimateError {
                            InlineError(message: estimateError)
                        }
                    }
                    .padding()
                    .cardSurface()

                    if let lastResult {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last meal added")
                                .font(.footnote)
                                .foregroundStyle(.textSecondary)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lastResult.meal_name)
                                        .font(.headline)
                                        .foregroundStyle(.textPrimary)

                                    Text(
                                        "\(lastResult.calories.formatted()) calories"
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding()
                        .cardSurface()
                    }

                    Spacer(minLength: 30)
                }
                .padding()
            }
            .refreshable {
                await store.refresh()
            }
        }
    }

    /// A number from the summary, or a dash before there is one.
    private static func number(_ value: Int?) -> String {
        value.map { $0.formatted() } ?? "–"
    }

    private func estimateMeal() {

        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        let submittedMeal = mealText.trimmingCharacters(in: .whitespacesAndNewlines)

        let imageData = photo.photo?.jpeg
        let sentPick = photo.photoPick

        isLoading = true
        estimateError = nil

        Task {
            do {
                let result = try await store.logMeal(
                    // No text for a photo-only meal: the server saves it
                    // without a description.
                    message: submittedMeal.isEmpty ? nil : submittedMeal,
                    imageData: imageData
                )
                lastResult = result

                mealText = ""
                // Keeps a photo picked while this estimate was running.
                photo.clearAfterEstimate(sentPick: sentPick)
            } catch {
                estimateError = error.localizedDescription
            }

            isLoading = false
        }
    }

    private func photoSourceLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            .accentTint,
            in: RoundedRectangle(cornerRadius: Radius.control)
        )
    }
}


struct CalorieRing: View {
    /// nil before today's summary has loaded: the ring is empty and shows a dash.
    let consumed: Int?
    let goal: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 44

    var progress: Double {
        guard let consumed, let goal, goal > 0 else {
            return 0
        }

        return min(Double(consumed) / Double(goal), 1)
    }

    var remaining: String {
        guard let consumed, let goal else {
            return "–"
        }

        return max(goal - consumed, 0).formatted()
    }

    /// What VoiceOver reads after "Calories left".
    static func accessibilityValue(consumed: Int?, goal: Int?) -> String {
        guard let consumed, let goal else {
            return "Not loaded yet"
        }

        return "\(max(goal - consumed, 0).formatted()) of \(goal.formatted())"
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    .hairline,
                    lineWidth: 20
                )

            Circle()
                .trim(
                    from: 0,
                    to: progress
                )
                .stroke(
                    .ring,
                    style: StrokeStyle(
                        lineWidth: 20,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.6),
                    value: progress
                )

            VStack(spacing: 4) {
                Text(remaining)
                    .font(
                        .system(
                            size: numberSize,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("calories left")
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            // Inside the ring's 220-point opening, so large text shrinks
            // rather than crossing the stroke.
            .frame(maxWidth: 170)
        }
        .frame(
            maxWidth: .infinity
        )
        .frame(height: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories left")
        .accessibilityValue(
            Self.accessibilityValue(consumed: consumed, goal: goal)
        )
    }
}


struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.textSecondary)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .numeric()
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}


/// Why today's data couldn't be refreshed, with a Retry. Shown above
/// whatever data is already on screen, which stays visible.
struct LoadErrorBanner: View {
    let title: String
    let message: String
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.danger)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)

                Button {
                    retry()
                } label: {
                    if isRetrying {
                        ProgressView()
                    } else {
                        Text("Retry")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(minHeight: 44))
                .disabled(isRetrying)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            .dangerSurface,
            in: RoundedRectangle(cornerRadius: Radius.card)
        )
    }
}


struct ContentView: View {
    @Environment(NutritionStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

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
        .task {
            await store.refresh()
        }
        // Coming back to the app (from Settings, Control Center, another app
        // or a new day) is when data goes stale or the network has changed.
        // Refreshes are shared, so this can't double up with the one above.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.refresh() }
            }
        }
    }
}

#Preview("Components, light") {
    ComponentsPreview()
}

#Preview("Components, dark") {
    ComponentsPreview()
        .preferredColorScheme(.dark)
}

#Preview("Components, largest text") {
    ComponentsPreview()
        .dynamicTypeSize(.accessibility5)
}

/// The shared pieces in their states, for the previews above.
private struct ComponentsPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CalorieRing(consumed: 1240, goal: 2633)
                CalorieRing(consumed: nil, goal: nil)

                HStack(spacing: 12) {
                    StatCard(title: "Consumed", value: "1,240")
                    StatCard(title: "Remaining", value: "1,393")
                    StatCard(title: "Goal", value: "2,633")
                }

                LoadErrorBanner(
                    title: "Couldn't update today's totals.",
                    message: "Can't reach the server.",
                    isRetrying: false
                ) {}

                InlineError(message: "Meal estimation is not available right now.")

                Button {} label: {
                    Text("Estimate Meal").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {} label: {
                    Text("Estimate Meal").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)
            }
            .padding()
        }
        .background(Color.appBackground)
    }
}
