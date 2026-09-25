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
    @State private var forceOnboarding = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text("Unable to load profile")
                        .font(.headline)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let profile {
                if profile.onboardingComplete && !forceOnboarding{
                    ContentView()
                } else {
                    OnboardingView {
                        forceOnboarding = false
                        
                        Task {
                            await loadProfile()
                        }
                    }
                }
            }
        }
        .task {
            await loadProfile()
        }
    }

    private func loadProfile() async {
        do {
            profile = try await NutritionAPI.shared.getUserProfile()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
