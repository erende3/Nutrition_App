import PhotosUI
import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(NutritionStore.self) private var store

    @State private var mealText = ""
    @State private var lastResult: NutritionEstimate?

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
            Color(red: 0.04, green: 0.05, blue: 0.08)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("TODAY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.gray)

                            // Only before the first load; later refreshes keep the numbers.
                            if store.summary == nil && store.isRefreshing {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }

                        Text("Nutrition")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
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
                        consumed: store.summary?.calories_consumed,
                        goal: store.summary?.daily_goal
                    )

                    HStack(spacing: 12) {
                        StatCard(
                            title: "Consumed",
                            value: Self.number(store.summary?.calories_consumed)
                        )

                        StatCard(
                            title: "Remaining",
                            value: Self.number(store.summary?.calories_remaining)
                        )

                        StatCard(
                            title: "Goal",
                            value: Self.number(store.summary?.daily_goal)
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
                        .focused($isMealFieldFocused)
                        .padding()
                        .foregroundStyle(.white)
                        .background(
                            Color.white.opacity(0.07)
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16)
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
                        .foregroundStyle(.white)
                        if photo.isPreparing {
                            HStack {
                                ProgressView()
                                Text("Preparing photo...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

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
                                        photo.remove()
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
                            Text(photoError)
                                .foregroundStyle(.red)
                        }

                        if let estimateError {
                            Text(estimateError)
                                .foregroundStyle(.red)
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

                    Spacer(minLength: 30)
                }
                .padding()
            }
            .refreshable {
                await store.refresh()
            }
        }
        .preferredColorScheme(.dark)
    }

    /// A number from the summary, or a dash before there is one.
    private static func number(_ value: Int?) -> String {
        value.map(String.init) ?? "–"
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
                    message: submittedMeal.isEmpty
                        ? "Estimate this meal from the image."
                        : submittedMeal,
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
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.10))
        .clipShape(
            RoundedRectangle(cornerRadius: 16)
        )
    }
}


struct CalorieRing: View {
    /// nil before today's summary has loaded: the ring is empty and shows a dash.
    let consumed: Int?
    let goal: Int?

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

        return "\(max(goal - consumed, 0))"
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
                Text(remaining)
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


/// Why today's data couldn't be refreshed, with a Retry. Shown above
/// whatever data is already on screen, which stays visible.
struct LoadErrorBanner: View {
    let title: String
    let message: String
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                retry()
            } label: {
                if isRetrying {
                    ProgressView()
                } else {
                    Text("Retry")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.15))
        .clipShape(
            RoundedRectangle(cornerRadius: 14)
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
