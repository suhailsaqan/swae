//
//  GuestProfileOverlay.swift
//  swae
//
//  Shown on the profile tab when no user is logged in.
//

import NostrSDK
import SwiftUI

struct GuestProfileOverlay: View {
    let appState: AppState

    @State private var showingCreateProfile = false
    @State private var showingSignIn = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Swae")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.purple)
                .padding(.top, 24)

            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(.secondary.opacity(0.5))

                Text("Your Profile")
                    .font(.system(size: 24, weight: .bold))

                Text("Create an account or sign in to start streaming, follow creators, and send zaps.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Button(action: { showingCreateProfile = true }) {
                    Text("Create Profile")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.purple)
                        .cornerRadius(14)
                }
                .padding(.top, 12)

                Button(action: { showingSignIn = true }) {
                    Text("Already have an account? Sign In")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .sheet(isPresented: $showingSignIn) {
            NavigationStack { SignInView() }
                .environmentObject(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCreateProfile) {
            NavigationStack {
                CreateProfileView(appState: appState)
            }
            .environmentObject(appState)
        }
    }
}
