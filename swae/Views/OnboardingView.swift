//
//  OnboardingView.swift
//  swae
//
//  Created by Suhail Saqan on 4/12/25.
//

import SwiftUI
import Kingfisher
import NostrSDK

struct OnboardingStep {
    let image: String
    let title: String
    let description: String
}

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    
    // Control whether onboarding is shown
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    // Control which step is currently displayed
    @State private var currentStep = 0
    
    // States for profile creation
    @State private var credentialHandler: CredentialHandler
    @State private var keypair: Keypair = Keypair.init()!
    @State private var username: String = ""
    @State private var displayName: String = ""
    @State private var about: String = ""
    @State private var picture: String = ""
    @State private var hasCopiedPublicKey: Bool = false
    @State private var hasCopiedPrivateKey: Bool = false
    @State private var showingKeyBackupAlert: Bool = false
    
    // Define your onboarding steps
    let onboardingSteps = [
        OnboardingStep(
            image: "play.circle.fill",
            title: "Watch Videos",
            description: "Stream the latest content from creators around the world"
        ),
        OnboardingStep(
            image: "tv.and.mediabox.fill",
            title: "Go Live",
            description: "Create and share your own livestreams with your followers"
        ),
        OnboardingStep(
            image: "person.2.fill",
            title: "Connect",
            description: "Follow your favorite creators and build your community"
        ),
        OnboardingStep(
            image: "wallet.pass.fill",
            title: "Support Creators",
            description: "Use the integrated wallet to support creators you love"
        )
    ]
    
    init(appState: AppState) {
        self.credentialHandler = CredentialHandler(appState: appState)
    }
    
    var validatedPictureURL: URL? {
        guard let url = URL(string: picture.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return url
    }
    
    var canCreateProfile: Bool {
        return username.trimmedOrNilIfEmpty != nil && (picture.trimmedOrNilIfEmpty == nil || validatedPictureURL != nil)
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // The content changes depending on if we're on the profile creation step
                if currentStep < onboardingSteps.count {
                    // App title/logo
                    Text("SwaeApp")
                        .font(.system(size: 35, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                        .padding(.top, 50)
                    
                    // Feature introduction content
                    Spacer()
                    
                    // Image for current step
                    Image(systemName: onboardingSteps[currentStep].image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .foregroundColor(.blue)
                        .padding()
                    
                    // Title for current step
                    Text(onboardingSteps[currentStep].title)
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    // Description for current step
                    Text(onboardingSteps[currentStep].description)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                    
                    Spacer()
                    
                    // Page indicator
                    HStack(spacing: 10) {
                        ForEach(0..<onboardingSteps.count + 1, id: \.self) { index in
                            Circle()
                                .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.5))
                                .frame(width: 10, height: 10)
                                .animation(.easeInOut, value: currentStep)
                        }
                    }
                    .padding(.bottom, 20)
                    
                    // Next button or Get Started button
                    Button(action: {
                        withAnimation {
                            currentStep += 1
                        }
                    }) {
                        Text("Next")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
                    
                    // Skip button
                    Button("Skip") {
                        withAnimation {
                            currentStep = onboardingSteps.count
                        }
                    }
                    .foregroundColor(.gray)
                    .padding(.bottom, 40)
                    
                } else {
                    // Profile creation step
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Header
                            Text("Create Your Profile")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                            
                            Text("Almost there! Set up your identity to get started.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.bottom, 10)
                            
                            // Username field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Username")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                TextField("Enter a username", text: $username)
                                    .padding()
                                    .background(.secondary.opacity(0.2))
                                    .cornerRadius(10)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                            }
                            
                            // Display name field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Display Name (Optional)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                TextField("Enter a display name", text: $displayName)
                                    .padding()
                                    .background(.secondary.opacity(0.2))
                                    .cornerRadius(10)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.words)
                                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                            }
                            
                            // Profile picture field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Profile Picture URL (Optional)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                TextField("https://example.com/image.png", text: $picture)
                                    .padding()
                                    .background(.secondary.opacity(0.2))
                                    .cornerRadius(10)
                                    .textContentType(.URL)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                                
                                if let validatedPictureURL = validatedPictureURL {
                                    HStack {
                                        Spacer()
                                        KFImage.url(validatedPictureURL)
                                            .resizable()
                                            .placeholder { ProgressView() }
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 80, height: 80)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: 3)
                                            )
                                            .shadow(radius: 3)
                                        Spacer()
                                    }
                                    .padding(.top, 10)
                                }
                            }
                            
                            // Keys section
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Your Keys")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                VStack(spacing: 12) {
                                    // Public key
                                    Button(action: {
                                        UIPasteboard.general.string = keypair.publicKey.npub
                                        hasCopiedPublicKey = true
                                    }, label: {
                                        HStack {
                                            Text("Public Key")
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text(keypair.publicKey.npub.prefix(8) + "..." + keypair.publicKey.npub.suffix(8))
                                                .foregroundColor(.secondary)
                                            Image(systemName: hasCopiedPublicKey ? "doc.on.doc.fill" : "doc.on.doc")
                                                .foregroundColor(.blue)
                                        }
                                        .padding()
                                        .background(.secondary.opacity(0.2))
                                        .cornerRadius(10)
                                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                                    })
                                    
                                    // Private key
                                    Button(action: {
                                        UIPasteboard.general.string = keypair.privateKey.nsec
                                        hasCopiedPrivateKey = true
                                    }, label: {
                                        HStack {
                                            Text("Private Key")
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text(keypair.privateKey.nsec.prefix(8) + "..." + keypair.privateKey.nsec.suffix(8))
                                                .foregroundColor(.secondary)
                                            Image(systemName: hasCopiedPrivateKey ? "doc.on.doc.fill" : "doc.on.doc")
                                                .foregroundColor(.blue)
                                        }
                                        .padding()
                                        .background(.secondary.opacity(0.2))
                                        .cornerRadius(10)
                                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                                    })
                                }
                                
                                Text("Make sure to save your private key somewhere secure. You won't be able to recover it later.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 4)
                            }
                            
                            // Create profile button
                            Button(action: {
                                showingKeyBackupAlert = true
                                
                            }) {
                                Text("Create Profile")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(canCreateProfile ? Color.blue : Color.gray)
                                    .cornerRadius(12)
                            }
                            .disabled(!canCreateProfile)
                            .padding(.top, 10)
                            .padding(.bottom, 40)
                            .alert("Confirm Key Backup", isPresented: $showingKeyBackupAlert) {
                                Button("I've Saved My Keys", role: .destructive) {
                                    createProfile()
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text("Have you saved your private key securely? You will not be able to recover your account without it.")
                            }
                        }
                        .padding(.horizontal, 30)
                    }
                }
            }
        }
    }
    
    func createProfile() {
        credentialHandler.saveCredential(keypair: keypair)
        appState.privateKeySecureStorage.store(for: keypair)
        let userMetadata = UserMetadata(name: username.trimmedOrNilIfEmpty, displayName: displayName.trimmedOrNilIfEmpty, pictureURL: validatedPictureURL)

        do {
            let readRelayURLs = appState.relayReadPool.relays.map { $0.url }
            let writeRelayURLs = appState.relayWritePool.relays.map { $0.url }

            let metadataEvent = try appState.metadataEvent(withUserMetadata: userMetadata, signedBy: keypair)
            let followListEvent = try appState.followList(withPubkeys: [keypair.publicKey.hex], signedBy: keypair)
            appState.relayWritePool.publishEvent(metadataEvent)
            appState.relayWritePool.publishEvent(followListEvent)

            let persistentNostrEvents = [
                PersistentNostrEvent(nostrEvent: metadataEvent),
                PersistentNostrEvent(nostrEvent: followListEvent)
            ]
            persistentNostrEvents.forEach {
                appState.modelContext.insert($0)
            }

            try appState.modelContext.save()

            appState.loadPersistentNostrEvents(persistentNostrEvents)

            appState.signIn(keypair: keypair, relayURLs: Array(Set(readRelayURLs + writeRelayURLs)))
            
            // Mark onboarding as completed
            hasCompletedOnboarding = true
            
        } catch {
            print("Unable to publish or save MetadataEvent for new profile \(keypair.publicKey.npub).")
        }
    }
}
