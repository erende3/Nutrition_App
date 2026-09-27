//
//  RootView.swift
//  MyNutritionPal
//
//  Created by Eric Rende on 9/1/26.
//


import SwiftUI

struct RootView: View {
    @State private var profile: UserProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text("Unable to load profile")
                        .font(.headline)
                        .foregroundStyle(.textPrimary)

                    Text(errorMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.textSecondary)

                    Button("Retry") {
                        isLoading = true

                        Task {
                            await loadProfile()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(minHeight: 44))
                }
                .padding()
            } else if let profile {
                if profile.onboardingComplete {
                    ContentView()
                } else {
                    OnboardingView {
                        Task {
                            await loadProfile()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .task {
            await loadProfile()
        }
    }

    private func loadProfile() async {
        do {
            profile = try await APIClient.shared.getUserProfile()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
