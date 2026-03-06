//
//  SettingsView.swift
//  swae
//
//  Created by Suhail Saqan on 2/19/25.
//

import NostrSDK
import SwiftData
import SwiftUI

struct AppSettingsView: View {
    @State private var viewModel: AppSettingsViewModel
    @State private var profileToSignOut: Profile?
    @State private var isShowingSignOutConfirmation = false
    @State private var isShowingAccountPicker = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    init(appState: AppState) {
        let viewModel = AppSettingsViewModel(appState: appState)
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Account Section
                accountSection
                
                // Profile Settings Section
                if viewModel.publicKeyHex != nil {
                    profileSettingsSection
                }
                
                // Sign Out Button
                if let activeProfile = viewModel.activeProfile,
                   activeProfile.publicKeyHex != nil {
                    signOutSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $viewModel.isSignInViewPresented) {
            NavigationStack { SignInView() }
                .environmentObject(viewModel.appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.isShowingCreateProfile) {
            NavigationStack {
                CreateProfileView(appState: viewModel.appState)
            }
            .environmentObject(viewModel.appState)
        }
        .sheet(isPresented: $isShowingAccountPicker) {
            accountPickerSheet
        }
        .confirmationDialog(
            "Add Account",
            isPresented: $viewModel.isShowingAddProfileOptions,
            titleVisibility: .visible
        ) {
            Button("Create New Profile") {
                viewModel.showCreateProfile()
            }
            Button("Sign Into Existing Profile") {
                viewModel.isSignInViewPresented = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            Text("Sign out of profile?"),
            isPresented: $isShowingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            if let profile = profileToSignOut {
                Button("Sign Out", role: .destructive) {
                    viewModel.signOut(profile)
                    profileToSignOut = nil
                }
                Button("Cancel", role: .cancel) {
                    profileToSignOut = nil
                }
            }
        } message: {
            Text("Your app settings will be deleted from this device. Your data on Nostr relays will not be affected.")
        }
    }
    
    // MARK: - Account Section
    var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "ACCOUNT", icon: "person.circle.fill")
            
            VStack(spacing: 0) {
                // Current Profile Card
                Button(action: { isShowingAccountPicker = true }) {
                    HStack(spacing: 12) {
                        // Profile Picture
                        if let publicKeyHex = viewModel.publicKeyHex,
                           PublicKey(hex: publicKeyHex) != nil {
                            ZStack(alignment: .bottomTrailing) {
                                ProfilePicView(
                                    pubkey: publicKeyHex,
                                    size: 56,
                                    profile: viewModel.activeProfileMetadata
                                )
                                
                                if !viewModel.isActiveProfileSignedInWithPrivateKey {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Color.purple)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 2)
                                        )
                                        .offset(x: 2, y: 2)
                                }
                            }
                        } else {
                            ZStack(alignment: .bottomTrailing) {
                                GuestProfilePictureView()
                                    .frame(width: 56, height: 56)
                                
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.purple)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(colorScheme == .dark ? Color.black : Color.white, lineWidth: 2)
                                    )
                                    .offset(x: 2, y: 2)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.activeProfileDisplayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(viewModel.activeProfileUsername)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if !viewModel.isActiveProfileSignedInWithPrivateKey {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye.fill")
                                        .font(.system(size: 10))
                                    Text("Read-only")
                                        .font(.caption)
                                }
                                .foregroundColor(.purple)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color.white)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Profile Settings Section
    var profileSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "PROFILE SETTINGS", icon: "lock.shield.fill")
            
            VStack(spacing: 0) {
                // Keys Setting
                if let publicKeyHex = viewModel.publicKeyHex,
                   let publicKey = PublicKey(hex: publicKeyHex) {
                    NavigationLink(destination: KeysSettingsView(publicKey: publicKey).environmentObject(viewModel.appState)) {
                        settingsRow(
                            icon: "key.fill",
                            iconColor: .orange,
                            title: "Keys",
                            subtitle: viewModel.isActiveProfileSignedInWithPrivateKey ? "Configured" : "Read-only",
                            showDivider: true
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Relays Setting
                NavigationLink(destination: RelaysSettingsView().environmentObject(viewModel.appState)) {
                    settingsRow(
                        icon: "antenna.radiowaves.left.and.right",
                        iconColor: .blue,
                        title: "Relays",
                        subtitle: viewModel.relayStatusText,
                        showDivider: false
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color.white)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Sign Out Section
    var signOutSection: some View {
        Button(action: {
            if let activeProfile = viewModel.activeProfile {
                profileToSignOut = activeProfile
                isShowingSignOutConfirmation = true
            }
        }) {
            HStack {
                Spacer()
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.headline)
                Spacer()
            }
            .foregroundColor(.red)
            .padding(16)
            .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color.white)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Account Picker Sheet
    var accountPickerSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.profiles, id: \.self) { profile in
                        Button(action: {
                            viewModel.appState.updateActiveProfile(profile)
                            isShowingAccountPicker = false
                        }) {
                            HStack(spacing: 12) {
                                // Profile Picture
                                if let publicKeyHex = profile.publicKeyHex,
                                   PublicKey(hex: publicKeyHex) != nil {
                                    ZStack(alignment: .bottomTrailing) {
                                        ProfilePicView(
                                            pubkey: publicKeyHex,
                                            size: 44,
                                            profile: viewModel.appState.metadataEvents[publicKeyHex]?.userMetadata
                                        )
                                        
                                        if !viewModel.isSignedInWithPrivateKey(profile) {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white)
                                                .frame(width: 16, height: 16)
                                                .background(Color.purple)
                                                .clipShape(Circle())
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: 2)
                                                )
                                                .offset(x: 2, y: 2)
                                        }
                                    }
                                } else {
                                    ZStack(alignment: .bottomTrailing) {
                                        GuestProfilePictureView()
                                            .frame(width: 44, height: 44)
                                        
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white)
                                            .frame(width: 16, height: 16)
                                            .background(Color.purple)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: 2)
                                            )
                                            .offset(x: 2, y: 2)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.profileDisplayName(for: profile))
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Text(viewModel.profileUsername(for: profile))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if viewModel.isActiveProfile(profile) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.purple)
                                        .font(.system(size: 20))
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if profile.publicKeyHex != nil {
                                Button(role: .destructive) {
                                    profileToSignOut = profile
                                    isShowingSignOutConfirmation = true
                                    isShowingAccountPicker = false
                                } label: {
                                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        isShowingAccountPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            viewModel.showAddProfileOptions()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.purple)
                            
                            Text("Add Account")
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Switch Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isShowingAccountPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Helper Views
    func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.secondary)
        .padding(.leading, 4)
    }
    
    func settingsRow(icon: String, iconColor: Color, title: String, subtitle: String, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(iconColor)
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            
            if showDivider {
                Divider()
                    .padding(.leading, 60)
            }
        }
    }
}

extension AppSettingsView {
    @Observable class AppSettingsViewModel {
        let appState: AppState
        var isSignInViewPresented: Bool = false
        var isShowingAddProfileOptions: Bool = false
        var isShowingCreateProfile: Bool = false

        init(appState: AppState) {
            self.appState = appState
        }

        var publicKeyHex: String? {
            appState.appSettings?.activeProfile?.publicKeyHex
        }

        var activeProfile: Profile? {
            appState.appSettings?.activeProfile
        }

        var profiles: [Profile] {
            appState.profiles
        }

        var activeProfileMetadata: UserMetadata? {
            guard let activeProfilePublicKeyHex = appState.appSettings?.activeProfile?.publicKeyHex
            else {
                return nil
            }
            return appState.metadataEvents[activeProfilePublicKeyHex]?.userMetadata
        }
        
        var activeProfileDisplayName: String {
            if let metadata = activeProfileMetadata {
                return metadata.displayName ?? metadata.name ?? appState.appSettings?.activeProfile?.cachedDisplayName ?? "Anonymous"
            }
            return appState.appSettings?.activeProfile?.cachedDisplayName ?? "Guest"
        }
        
        var activeProfileUsername: String {
            if let metadata = activeProfileMetadata {
                return "@\(metadata.name ?? appState.appSettings?.activeProfile?.cachedUsername ?? "anonymous")"
            }
            return "@\(appState.appSettings?.activeProfile?.cachedUsername ?? "guest")"
        }
        
        var relayStatusText: String {
            guard let relaySettings = appState.relayPoolSettings?.relaySettingsList else {
                return "No relays"
            }
            
            let connectedCount = relaySettings.filter { relaySettings in
                if case .connected = appState.relayState(relayURLString: relaySettings.relayURLString) {
                    return true
                }
                return false
            }.count
            
            let total = relaySettings.count
            
            if connectedCount == 0 {
                return "\(total) relay\(total == 1 ? "" : "s")"
            }
            return "\(connectedCount)/\(total) connected"
        }

        var isActiveProfileSignedInWithPrivateKey: Bool {
            guard let activeProfile = appState.appSettings?.activeProfile else {
                return false
            }
            return isSignedInWithPrivateKey(activeProfile)
        }

        func isSignedInWithPrivateKey(_ profile: Profile) -> Bool {
            guard let publicKeyHex = profile.publicKeyHex,
                let publicKey = PublicKey(hex: publicKeyHex)
            else {
                return false
            }
            return PrivateKeySecureStorage.shared.keypair(for: publicKey) != nil
        }

        func signOut(_ profile: Profile) {
            let wasLastProfile = profiles.count == 1
            appState.deleteProfile(profile)
            if wasLastProfile {
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            }
        }

        func isActiveProfile(_ profile: Profile) -> Bool {
            return appState.appSettings?.activeProfile == profile
        }
        
        func profileDisplayName(for profile: Profile) -> String {
            // Prefer live relay metadata, fall back to cached
            if let publicKeyHex = profile.publicKeyHex,
               let metadata = appState.metadataEvents[publicKeyHex]?.userMetadata {
                return metadata.displayName ?? metadata.name ?? profile.cachedDisplayName ?? "Anonymous"
            }
            return profile.cachedDisplayName ?? "Guest"
        }
        
        func profileUsername(for profile: Profile) -> String {
            if let publicKeyHex = profile.publicKeyHex,
               let metadata = appState.metadataEvents[publicKeyHex]?.userMetadata {
                return "@\(metadata.name ?? profile.cachedUsername ?? "anonymous")"
            }
            return "@\(profile.cachedUsername ?? "guest")"
        }
        
        func showAddProfileOptions() {
            isShowingAddProfileOptions = true
        }
        
        func showCreateProfile() {
            isShowingCreateProfile = true
        }
    }
}
