//
//  ContentView.swift
//  swae
//
//  Created by Suhail Saqan on 8/11/24.
//

import AVFoundation
import NostrSDK
import SwiftData
import SwiftUI

struct ContentView: View {
    let modelContext: ModelContext

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var orientationMonitor: OrientationMonitor
    @EnvironmentObject var model: Model

    @AppStorage("ContentView.selected_tab") var selected_tab: ScreenTabs = .home

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @State var hide_bar: Bool = false
    @State var isInMainView: Bool = false
    @State var navigationState: InstagramNavigationState = .feedVisible
    // Note: cameraContainerState removed - CameraContainerViewController is now managed directly by InstagramNavigationController
    // Requirements: 8.1

    // Camera lifecycle management
    @State private var isCameraAttached: Bool = false
    @State private var isAudioAttached: Bool = false
    @State private var cameraDetachTask: Task<Void, Never>? = nil
    @State private var hasInitializedCamera: Bool = false
    @State private var shouldAttachAudioWithCamera: Bool = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingViewControllerRepresentable(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(appState)
                    .ignoresSafeArea()
            } else {
                MainAppView()
            }
        }
        .appFont()
    }

    // Feature flag for UIKit camera (set to true to use new UIKit-based camera)
    private let useUIKitCamera = true
    
    func MainAppView() -> some View {
        ZStack(alignment: .bottom) {
            // Instagram-style navigation
            // Model is passed directly to InstagramNavigationView which creates CameraContainerViewController
            // without SwiftUI wrapper (Requirements: 8.1)
            if useUIKitCamera {
                InstagramNavigationViewUIKit(
                    feedView: createFeedView(),
                    cameraViewController: createCameraViewController(),
                    model: model,
                    navigationState: $navigationState
                )
            } else {
                InstagramNavigationView(
                    feedView: createFeedView(),
                    cameraView: AnyView(createMainView()),
                    model: model,
                    navigationState: $navigationState
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            isInMainView = true
            // Setup model but don't attach camera yet
            if !hasInitializedCamera {
                // Tell Model that ContentView will manage audio lifecycle - MUST BE SET BEFORE setup()
                model.audioManagedByContentView = true
                // Fast path: only feed essentials (~50ms instead of ~500ms)
                model.setupMinimal()
                hasInitializedCamera = true

                // Defer heavy camera/streaming setup to after the first frame renders.
                // Task.yield() lets the run loop complete the first layout pass before
                // we start Bluetooth, camera enumeration, stream processor, etc.
                Task { @MainActor in
                    await Task.yield()
                    model.setupDeferred()
                }
            }
        }
        .onDisappear {
            isInMainView = false
            // Clean up any pending detach tasks
            cameraDetachTask?.cancel()
            cameraDetachTask = nil
        }
        .onChange(of: navigationState) { oldState, newState in
            handleNavigationStateChange(oldState: oldState, newState: newState)
        }
        .onChange(of: model.isLive) { _, isLive in
            if isLive {
                // User started streaming - ensure we track that camera and audio are attached
                isCameraAttached = true
                isAudioAttached = true
                cameraDetachTask?.cancel()
                cameraDetachTask = nil
                print("📷 Stream started - camera and audio are now attached")
            }
        }
        .onChange(of: model.streaming) { _, streaming in
            if streaming {
                // User started streaming - ensure we track that camera and audio are attached
                isCameraAttached = true
                isAudioAttached = true
                cameraDetachTask?.cancel()
                cameraDetachTask = nil
                print("📷 Stream started - camera and audio are now attached")
            }
        }
        .onChange(of: model.collabCallState.isActive) { _, isActive in
            if isActive {
                // Collab call became active - ensure camera and audio stay attached
                isCameraAttached = true
                isAudioAttached = true
                cameraDetachTask?.cancel()
                cameraDetachTask = nil
                print("📷 Collab call active - camera and audio are now attached")
            }
        }
        .onChange(of: model.needsCameraReattach) { _, needsReattach in
            if needsReattach {
                model.needsCameraReattach = false
                // stopAll() destroyed the old Processor/VideoUnit. The new one
                // created by reloadStream() has no camera inputs. Reset our
                // tracking so attachCameraIfNeeded() will actually run.
                isCameraAttached = false
                isAudioAttached = false
                if navigationState == .cameraVisible || navigationState == .transitioning {
                    attachCameraIfNeeded()
                }
            }
        }
        .onReceive(handle_notify(.display_tabbar)) { display in
            let show = display
            self.hide_bar = !show
        }
        .onReceive(handle_notify(.unfollow)) { target in
            if appState.saveFollowList(pubkeys: target) {
                notify(.unfollowed(target))
            } else {
                // Error: revert by sending followed with original list
                if let originalList = appState.activeFollowList?.followedPubkeys {
                    notify(.followed(originalList))
                }
            }
        }
        .onReceive(handle_notify(.unfollowed)) { newFollowList in
            // newFollowList is the complete new follow list after unfollowing
            // Replace the entire set with the new list
            appState.followedPubkeys = Set(newFollowList)
            if let publicKey = appState.publicKey {
                appState.followedPubkeys.insert(publicKey.hex)
            }
        }
        .onReceive(handle_notify(.follow)) { target in
            if appState.saveFollowList(pubkeys: target) {
                notify(.followed(target))
            } else {
                // Error: revert by sending unfollowed with original list
                if let originalList = appState.activeFollowList?.followedPubkeys {
                    notify(.unfollowed(originalList))
                }
            }
        }
        .onReceive(handle_notify(.followed)) { newFollowList in
            // newFollowList is the complete new follow list after following
            // Replace the entire set with the new list
            appState.followedPubkeys = Set(newFollowList)
            if let publicKey = appState.publicKey {
                appState.followedPubkeys.insert(publicKey.hex)
            }
        }
        .onReceive(handle_notify(.attached_wallet)) { nwc in
            // Update the lightning address on our profile when we connect a wallet
            if let lud16 = nwc.lud16, let keypair = appState.keypair {
                Task {
                    do {
                        // Read existing profile as raw dictionary to preserve ALL fields
                        let existingRaw = appState.metadataEvents[keypair.publicKey.hex]?.rawUserMetadata ?? [:]

                        // Only publish if lud16 is actually different
                        let currentLud16 = existingRaw["lud16"] as? String
                        if currentLud16 != lud16 {
                            // Create UserMetadata with ONLY the lud16 we want to set
                            let userMetadata = UserMetadata(lightningAddress: lud16)

                            // Build event — merging puts lud16 into the existing dict, everything else untouched
                            let metadataEvent = try MetadataEvent.Builder()
                                .userMetadata(userMetadata, merging: existingRaw)
                                .build(signedBy: keypair)

                            // Publish to relays
                            appState.relayWritePool.publishEvent(metadataEvent)

                            // Update local cache
                            await MainActor.run {
                                appState.processMetadataDirect(metadataEvent)
                            }

                            print("⚡ Updated profile with lightning address: \(lud16)")
                        }
                    } catch {
                        print("❌ Failed to update profile with lightning address: \(error)")
                    }
                }
            }

            // Add NWC relay to read and write
            appState.addRelay(relayURL: nwc.relay.url)
        }
        .onReceive(handle_notify(.spark_wallet_attached)) { lud16 in
            // Update the lightning address on our profile when Spark wallet connects
            guard let keypair = appState.keypair else { return }

            Task {
                do {
                    let existingRaw = appState.metadataEvents[keypair.publicKey.hex]?.rawUserMetadata ?? [:]
                    let currentLud16 = existingRaw["lud16"] as? String
                    if currentLud16 != lud16 {
                        let userMetadata = UserMetadata(lightningAddress: lud16)
                        let metadataEvent = try MetadataEvent.Builder()
                            .userMetadata(userMetadata, merging: existingRaw)
                            .build(signedBy: keypair)
                        appState.relayWritePool.publishEvent(metadataEvent)
                        await MainActor.run {
                            appState.processMetadataDirect(metadataEvent)
                        }
                        print("⚡ Updated profile with Spark lightning address: \(lud16)")
                    }
                } catch {
                    print("❌ Failed to update profile with Spark lightning address: \(error)")
                }
            }
        }
        .onReceive(handle_notify(.detached_wallet)) { lud16 in
            // Remove the lightning address from our profile when we disconnect a wallet
            guard let keypair = appState.keypair else { return }

            Task {
                do {
                    let existingRaw = appState.metadataEvents[keypair.publicKey.hex]?.rawUserMetadata ?? [:]

                    // Only publish if there's actually a lud16 to remove
                    guard let currentLud16 = existingRaw["lud16"] as? String, !currentLud16.isEmpty else { return }

                    // If we know the lud16 that was disconnected, only remove if it matches
                    // (don't remove a manually-set lightning address from a different provider)
                    if let disconnectedLud16 = lud16, currentLud16 != disconnectedLud16 {
                        return
                    }

                    // Remove lud16 from the raw metadata
                    var updatedRaw = existingRaw
                    updatedRaw.removeValue(forKey: "lud16")

                    // Build a UserMetadata with no lightning address
                    let userMetadata = UserMetadata()

                    let metadataEvent = try MetadataEvent.Builder()
                        .userMetadata(userMetadata, merging: updatedRaw)
                        .build(signedBy: keypair)

                    appState.relayWritePool.publishEvent(metadataEvent)

                    await MainActor.run {
                        appState.processMetadataDirect(metadataEvent)
                    }

                    print("⚡ Removed lightning address from profile")
                } catch {
                    print("❌ Failed to remove lightning address from profile: \(error)")
                }
            }
        }
    }

    private func createFeedView() -> InstagramFeedView {
        InstagramFeedView(
            selectedTab: $selected_tab,
            onCameraButtonTapped: {
                // Camera button removed - no action needed
            }
        )
    }

    // Note: createCameraContainer() removed - CameraContainerViewController is now created directly
    // by InstagramNavigationController without SwiftUI wrapper (Requirements: 8.1)

    /// Creates the new UIKit-based CameraViewController
    private func createCameraViewController() -> CameraViewController {
        let streamView = StreamView(
            show: model.show,
            cameraPreviewView: CameraPreviewView(),
            streamPreviewView: StreamPreviewView()
        )
        
        let cameraVC = CameraViewController(
            model: model,
            streamView: streamView,
            orientation: model.orientation
        )
        
        // Note: Can't use weak self in struct - the callback will be handled by the navigation controller
        // The onExitStream callback is optional and navigation is handled by InstagramNavigationController
        
        return cameraVC
    }
    
    /// Legacy SwiftUI MainView creator (kept for fallback)
    private func createMainView() -> some View {
        MainView(
            webBrowserController: model.webBrowserController,
            streamView: StreamView(
                show: model.show,
                cameraPreviewView: CameraPreviewView(),
                streamPreviewView: StreamPreviewView()
            ),
            createStreamWizard: model.createStreamWizard,
            toast: model.toast,
            orientation: model.orientation,
            onExitStream: {
                // Return to feed
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                    navigationState = .feedVisible
                }
            }
        )
        .environmentObject(model)
        .environmentObject(appState)
    }

    // MARK: - Camera Lifecycle Management

    /// Manages camera lifecycle similar to Instagram/Snapchat:
    /// 1. Camera is OFF by default when app launches (user sees feed)
    /// 2. Camera turns ON immediately when user swipes to camera view
    /// 3. Camera turns OFF 1 second after user swipes back to feed
    /// 4. If user swipes back to camera before 1 second, the timer is cancelled
    /// 5. Camera stays ON if user is streaming/live, regardless of navigation state
    /// 6. This saves battery and resources when camera is not needed

    private func handleNavigationStateChange(
        oldState: InstagramNavigationState, newState: InstagramNavigationState
    ) {
        print("📷 Navigation state changed from \(oldState) to \(newState)")

        switch newState {
        case .cameraVisible:
            // User fully swiped into camera view - ensure camera is attached
            cameraDetachTask?.cancel()
            cameraDetachTask = nil
            attachCameraIfNeeded()

            // Camera is now fully visible — apply its desired orientation
            model.isCameraScreenVisible = true
            AppDelegate.orientationLock = model.cameraDesiredOrientationLock

        case .feedVisible:
            // Feed is now fully visible — force portrait.
            // This is the ONLY place we rotate to portrait. We do NOT rotate
            // during .transitioning because that would rotate the device mid-swipe,
            // breaking the gesture (the coordinate system changes while the user is dragging).
            model.isCameraScreenVisible = false
            AppDelegate.orientationLock = .portrait

            // Schedule camera detach after 1 second
            scheduleCameraDetachment()

        case .transitioning:
            if oldState == .feedVisible {
                // Transitioning FROM feed TO camera — attach camera but don't rotate yet
                print("📷 Transitioning from feed to camera - attaching camera now")
                cameraDetachTask?.cancel()
                cameraDetachTask = nil
                attachCameraIfNeeded()
            }
            // When transitioning FROM camera TO feed: do nothing here.
            // The orientation stays landscape until the feed is fully visible (.feedVisible).
            // This keeps the gesture coordinate system stable during the swipe.
        }
    }

    private func attachCameraIfNeeded() {
        guard !isCameraAttached else {
            print("📷 Camera already attached, skipping")
            return
        }

        // Regression guard: if the user swipes to camera before the deferred
        // setup Task has completed, run it synchronously now. This ensures
        // resetSelectedScene() has set a valid scene ID (required by
        // attachCamera → getSelectedScene) and the media processor exists.
        if !model.hasDeferredSetupCompleted {
            print("📷 Deferred setup not yet complete — running synchronously before camera attach")
            model.setupDeferred()
        }

        print("📷 Attaching camera and audio...")

        // Activate the full .playAndRecord audio session for microphone access.
        // This is deferred from app startup to avoid killing background music.
        model.setupAudioSession()

        // Attach audio device
        if !isAudioAttached {
            model.media.attachDefaultAudioDevice(
                builtinDelay: model.database.debug.builtinAudioAndVideoDelay)
            isAudioAttached = true
            print("🎤 Audio attached")
        }

        // Then attach camera
        model.attachCamera()
        isCameraAttached = true
    }

    private func detachCameraIfNeeded() {
        guard isCameraAttached || isAudioAttached else {
            print("📷 Camera and audio already detached, skipping")
            return
        }

        // Don't detach if user is streaming, live, or in a collab call
        if model.isLive || model.streaming || model.collabCallState.isActive {
            print("📷 Skipping camera/audio detach - user is streaming or in collab call")
            return
        }

        print("📷 Detaching camera and audio...")

        // Detach camera
        if isCameraAttached {
            model.detachCamera()
            isCameraAttached = false
        }

        // Detach audio device
        if isAudioAttached {
            model.media.detachDefaultAudioDevice()
            isAudioAttached = false
            print("🎤 Audio detached")
        }

        // Drop back to lightweight .playback session so background music
        // from other apps isn't interrupted while on the feed screen.
        model.setupFeedAudioSession()
    }

    private func scheduleCameraDetachment() {
        // Cancel any existing detach task
        cameraDetachTask?.cancel()

        print("📷 Scheduling camera detach in 1 second...")

        // Schedule new detach task
        cameraDetachTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

            // Check if task was cancelled
            guard !Task.isCancelled else {
                print("📷 Camera detach cancelled")
                return
            }

            // Ensure we're still on feed view (user didn't swipe back)
            guard navigationState == .feedVisible else {
                print("📷 Camera detach cancelled - user returned to camera")
                return
            }

            await MainActor.run {
                detachCameraIfNeeded()
            }
        }
    }

    // MARK: - Unused Code (App uses InstagramNavigationView → MainTabBarController instead)
    // func MainContent() -> some View {
    //     // This function is not called - tabs are managed by MainTabBarController
    // }
}

var safeArea: UIEdgeInsets {
    if let safeArea = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?
        .safeAreaInsets
    {
        return safeArea
    }

    return .zero
}
