//
//  CreateProfileView.swift
//  swae
//
//  Created by Suhail Saqan on 2/19/25.
//

import Kingfisher
import NostrSDK
import OrderedCollections
import SwiftUI

struct CreateProfileView: View, EventCreating {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appState: AppState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @State private var credentialHandler: CredentialHandler
    @State private var keypair: Keypair = Keypair.init()!

    @State private var currentStep: Int = 0
    @State private var username: String = ""
    @State private var about: String = ""
    @State private var displayName: String = ""

    // Image state
    @State private var pendingProfileImage: UIImage?
    @State private var pendingBannerImage: UIImage?
    @State private var profilePictureURL: String = ""
    @State private var bannerURL: String = ""

    // Key backup state
    @State private var hasCopiedPublicKey: Bool = false
    @State private var hasCopiedPrivateKey: Bool = false
    @State private var hasAcknowledgedBackup: Bool = false
    @State private var showingBackupWarning: Bool = false

    // Create profile state
    @State private var isCreating: Bool = false
    @State private var showUploadError: Bool = false
    @State private var uploadErrorMessage: String = ""

    init(appState: AppState) {
        credentialHandler = CredentialHandler(appState: appState)
    }

    var canProceedFromStep: Bool {
        switch currentStep {
        case 0: return username.trimmedOrNilIfEmpty != nil
        case 1: return true
        case 2: return hasCopiedPrivateKey && hasAcknowledgedBackup
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress Indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index <= currentStep ? Color.accentPurple : Color.gray.opacity(0.3))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 24) {
                        Group {
                            switch currentStep {
                            case 0: profileInfoStep
                            case 1: profileDetailsStep
                            case 2: backupKeysStep
                            default: EmptyView()
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 100)
                }

                // Bottom Navigation
                bottomNavigation
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Create Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Backup Your Keys", isPresented: $showingBackupWarning) {
                Button("I've Saved My Keys", role: .destructive) {
                    hasAcknowledgedBackup = true
                }
                Button("Go Back", role: .cancel) {}
            } message: {
                Text("Make sure you've copied and saved your private key. You won't be able to recover it later!")
            }
            .alert("Upload Failed", isPresented: $showUploadError) {
                Button("Try Again") { createProfile() }
                Button("Skip Photos", role: .destructive) {
                    pendingProfileImage = nil
                    pendingBannerImage = nil
                    createProfile()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(uploadErrorMessage)
            }
        }
    }

    // MARK: - Bottom Navigation

    private var bottomNavigation: some View {
        VStack(spacing: 12) {
            if currentStep < 2 {
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        currentStep += 1
                    }
                }) {
                    HStack {
                        Spacer()
                        Text(currentStep == 0 ? "Continue" : "Next")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(16)
                    .background(canProceedFromStep ? Color.accentPurple : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!canProceedFromStep)

                if currentStep > 0 {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) { currentStep -= 1 }
                    }) {
                        Text("Back")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Button(action: createProfile) {
                    HStack {
                        Spacer()
                        if isCreating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Create Profile")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(canProceedFromStep && !isCreating ? Color.accentPurple : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!canProceedFromStep || isCreating)

                Button(action: {
                    withAnimation(.spring(response: 0.3)) { currentStep -= 1 }
                }) {
                    Text("Back")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            colorScheme == .dark
                ? Color(UIColor.systemBackground)
                : Color(UIColor.systemGroupedBackground)
        )
    }

    // MARK: - Step 1: Profile Info

    var profileInfoStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentPurple)

                Text("Create Your Profile")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Choose a username to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(.headline)

                    TextField("Enter username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color.white)
                        .cornerRadius(10)

                    Text("Your username is how others will find you")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Name (Optional)")
                        .font(.headline)

                    TextField("Enter display name", text: $displayName)
                        .padding(12)
                        .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color.white)
                        .cornerRadius(10)

                    Text("A friendly name that appears on your profile")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Step 2: Profile Details (Banner + Profile Pic)

    var profileDetailsStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Customize Your Profile")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Add a profile picture and banner (optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Banner + Profile Pic preview (mirrors Edit Profile layout)
            profileImageHeader

            // Hint text
            Text("Tap the banner or profile picture to change them")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var profileImageHeader: some View {
        ZStack(alignment: .bottomLeading) {
            // Banner area
            bannerView
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { presentImagePicker(for: .banner) }

            // Profile pic overlapping bottom-left
            profilePicView
                .offset(x: 16, y: 30)
        }
        .padding(.bottom, 30) // room for the profile pic overhang
    }

    private var bannerView: some View {
        ZStack {
            GeometryReader { _ in
                if let bannerImage = pendingBannerImage {
                    Image(uiImage: bannerImage)
                        .resizable()
                        .scaledToFill()
                } else if let url = URL(string: bannerURL), !bannerURL.isEmpty {
                    KFImage.url(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Placeholder
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentPurple.opacity(0.3), Color.accentPurple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }

            // Camera overlay
            VStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())

                if pendingBannerImage == nil && bannerURL.isEmpty {
                    Text("Add Banner")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var profilePicView: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { _ in
                if let profileImage = pendingProfileImage {
                    Image(uiImage: profileImage)
                        .resizable()
                        .scaledToFill()
                } else if let url = URL(string: profilePictureURL), !profilePictureURL.isEmpty {
                    KFImage.url(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("swae")
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(UIColor.systemGroupedBackground), lineWidth: 3))

            // Purple camera badge
            ZStack {
                Circle()
                    .fill(Color.accentPurple)
                    .frame(width: 28, height: 28)

                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .onTapGesture { presentImagePicker(for: .profilePicture) }
    }

    // MARK: - Step 3: Backup Keys

    var backupKeysStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)

                Text("Backup Your Keys")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Save these keys securely - you'll need them to sign in")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Warning Box
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Important")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text("Your private key cannot be recovered if lost. Save it in a secure password manager.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(10)

            // Public Key
            VStack(alignment: .leading, spacing: 8) {
                Text("Public Key")
                    .font(.headline)

                Button(action: {
                    UIPasteboard.general.string = keypair.publicKey.npub
                    hasCopiedPublicKey = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        hasCopiedPublicKey = false
                    }
                }) {
                    HStack(spacing: 12) {
                        Text(keypair.publicKey.npub)
                            .font(.system(.caption, design: .monospaced))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: hasCopiedPublicKey ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundColor(hasCopiedPublicKey ? .green : .accentPurple)
                    }
                    .padding(12)
                    .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color.white)
                    .cornerRadius(10)
                }

                Text("Share this to let others find you")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Private Key
            VStack(alignment: .leading, spacing: 8) {
                Text("Private Key")
                    .font(.headline)

                Button(action: {
                    UIPasteboard.general.string = keypair.privateKey.nsec
                    hasCopiedPrivateKey = true
                }) {
                    HStack(spacing: 12) {
                        Text(keypair.privateKey.nsec)
                            .font(.system(.caption, design: .monospaced))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: hasCopiedPrivateKey ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundColor(hasCopiedPrivateKey ? .green : .accentPurple)
                    }
                    .padding(12)
                    .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color.white)
                    .cornerRadius(10)
                }

                Text("Keep this secret - it gives full access to your account")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Acknowledgment
            if hasCopiedPrivateKey {
                Button(action: {
                    showingBackupWarning = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: hasAcknowledgedBackup ? "checkmark.square.fill" : "square")
                            .foregroundColor(hasAcknowledgedBackup ? .accentPurple : .secondary)

                        Text("I've saved my private key securely")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Image Picker Presentation

    private func presentImagePicker(for type: ImageSourcePickerViewController.ImageType) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        // Walk to the topmost presented VC
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let hasExisting: Bool
        switch type {
        case .profilePicture:
            hasExisting = pendingProfileImage != nil || !profilePictureURL.isEmpty
        case .banner:
            hasExisting = pendingBannerImage != nil || !bannerURL.isEmpty
        case .streamCover:
            hasExisting = false
        }

        let picker = ImageSourcePickerViewController(imageType: type, hasExistingImage: hasExisting)
        let coordinator = ImagePickerCoordinator(
            imageType: type,
            onImageSelected: { [self] image in
                switch type {
                case .profilePicture:
                    pendingProfileImage = image
                    profilePictureURL = ""
                case .banner:
                    pendingBannerImage = image
                    bannerURL = ""
                case .streamCover:
                    break
                }
            },
            onURLEntered: { [self] url in
                switch type {
                case .profilePicture:
                    pendingProfileImage = nil
                    profilePictureURL = url.absoluteString
                case .banner:
                    pendingBannerImage = nil
                    bannerURL = url.absoluteString
                case .streamCover:
                    break
                }
            },
            onRemoved: { [self] in
                switch type {
                case .profilePicture:
                    pendingProfileImage = nil
                    profilePictureURL = ""
                case .banner:
                    pendingBannerImage = nil
                    bannerURL = ""
                case .streamCover:
                    break
                }
            }
        )
        picker.delegate = coordinator

        // Retain coordinator for the lifetime of the presentation
        objc_setAssociatedObject(picker, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        topVC.present(picker, animated: true)
    }

    // MARK: - Create Profile Action

    func createProfile() {
        isCreating = true

        Task {
            var finalPictureURL = profilePictureURL
            var finalBannerURL = bannerURL

            // Upload profile pic if pending
            if let profileImage = pendingProfileImage {
                do {
                    let url = try await ImageUploadManager.shared.uploadImage(
                        profileImage,
                        purpose: .profilePicture,
                        keypair: keypair
                    )
                    finalPictureURL = url.absoluteString
                } catch {
                    await MainActor.run {
                        isCreating = false
                        uploadErrorMessage = "Could not upload profile picture. Try again or skip."
                        showUploadError = true
                    }
                    return
                }
            }

            // Upload banner if pending
            if let bannerImage = pendingBannerImage {
                do {
                    let url = try await ImageUploadManager.shared.uploadImage(
                        bannerImage,
                        purpose: .banner,
                        keypair: keypair
                    )
                    finalBannerURL = url.absoluteString
                } catch {
                    await MainActor.run {
                        isCreating = false
                        uploadErrorMessage = "Could not upload banner image. Try again or skip."
                        showUploadError = true
                    }
                    return
                }
            }

            await MainActor.run {
                finishProfileCreation(pictureURL: finalPictureURL, bannerURL: finalBannerURL)
            }
        }
    }

    private func finishProfileCreation(pictureURL: String, bannerURL: String) {
        credentialHandler.saveCredential(keypair: keypair)

        let validatedPicture = URL(string: pictureURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let validatedBanner = URL(string: bannerURL.trimmingCharacters(in: .whitespacesAndNewlines))

        let userMetadata = UserMetadata(
            name: username.trimmedOrNilIfEmpty,
            displayName: displayName.trimmedOrNilIfEmpty,
            pictureURL: validatedPicture,
            bannerPictureURL: validatedBanner
        )

        do {
            let readRelayURLs = appState.relayReadPool.relays.map { $0.url }
            let writeRelayURLs = appState.relayWritePool.relays.map { $0.url }

            let metadataEvent = try metadataEvent(withUserMetadata: userMetadata, signedBy: keypair)
            let followListEvent = try followList(withPubkeys: [keypair.publicKey.hex], signedBy: keypair)
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

            // Cache display metadata on the newly created profile for offline account picker
            if let profile = appState.profiles.first(where: { $0.publicKeyHex == keypair.publicKey.hex }) {
                profile.cachedDisplayName = displayName.trimmedOrNilIfEmpty ?? username.trimmedOrNilIfEmpty
                profile.cachedUsername = username.trimmedOrNilIfEmpty
                profile.cachedProfilePictureURL = validatedPicture?.absoluteString
                try? appState.modelContext.save()
            }

            hasCompletedOnboarding = true
            isCreating = false

            // Auto-connect wallet in the background (existing onboarding UI stays as fallback)
            if WalletModel.useSparkBackend {
                appState.autoConnectSparkWallet(keypair: keypair)
            } else {
                appState.autoConnectCoinosWallet(keypair: keypair)
            }
        } catch {
            isCreating = false
            print("Unable to publish or save MetadataEvent for new profile \(keypair.publicKey.npub).")
        }

        dismiss()
    }
}

// MARK: - UIKit Bridge Coordinator

/// Bridges ImageSourcePickerDelegate and ImageCropperDelegate back to SwiftUI @State via closures.
final class ImagePickerCoordinator: NSObject, ImageSourcePickerDelegate, ImageCropperDelegate {

    private let imageType: ImageSourcePickerViewController.ImageType
    private let onImageSelected: (UIImage) -> Void
    private let onURLEntered: (URL) -> Void
    private let onRemoved: () -> Void

    init(
        imageType: ImageSourcePickerViewController.ImageType,
        onImageSelected: @escaping (UIImage) -> Void,
        onURLEntered: @escaping (URL) -> Void,
        onRemoved: @escaping () -> Void
    ) {
        self.imageType = imageType
        self.onImageSelected = onImageSelected
        self.onURLEntered = onURLEntered
        self.onRemoved = onRemoved
    }

    // MARK: - ImageSourcePickerDelegate

    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didEnterURL url: URL) {
        onURLEntered(url)
    }

    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didSelectImage image: UIImage) {
        let cropShape: CropOverlayView.CropShape
        switch imageType {
        case .profilePicture: cropShape = .circle
        case .banner: cropShape = .rect(aspectRatio: 3.0)
        case .streamCover: cropShape = .rect(aspectRatio: 16.0 / 9.0)
        }

        let cropper = ImageCropperViewController(image: image, cropShape: cropShape)
        cropper.cropDelegate = self

        // Retain coordinator on the cropper too
        objc_setAssociatedObject(cropper, "coordinator", self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Present cropper from the topmost VC
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        topVC.present(cropper, animated: true)
    }

    func imageSourcePickerDidRemoveImage(_ picker: ImageSourcePickerViewController) {
        onRemoved()
    }

    func imageSourcePickerDidCancel(_ picker: ImageSourcePickerViewController) {}

    // MARK: - ImageCropperDelegate

    func imageCropper(_ cropper: ImageCropperViewController, didCropImage image: UIImage) {
        onImageSelected(image)
    }

    func imageCropperDidCancel(_ cropper: ImageCropperViewController) {}
}
