//
//  VideoPlayerModel.swift
//  swae
//
//  Created by Suhail Saqan on 1/28/25.
//

import AVKit
import Combine
import SwiftUI

// The model that holds video-related properties and controls
class VideoPlayerModel: ObservableObject {
    @Published var player: AVPlayer
    @Published var isPlaying: Bool = false
    @Published var showPlayerControls: Bool = false
    @Published var progress: CGFloat = 0
    @Published var isFinishedPlaying: Bool = false
    @Published var isSeeking: Bool = false
    @Published var isLoading: Bool = false
    @Published var playerError: Bool = false
    @Published var thumbnailFrames: [UIImage] = []
    @Published var draggingImage: UIImage?
    @Published var isRotated: Bool = false
    @Published var lastDraggedProgress: CGFloat = 0
    @Published var timeoutTask: DispatchWorkItem?
    @Published var isObserverAdded: Bool = false
    @Published var playerStatusObserver: NSKeyValueObservation?
    @Published var isInMiniPlayerMode: Bool = false
    @Published var shouldOptimizeForMiniPlayer: Bool = false
    @Published var detectedVideoSize: CGSize = .zero
    @Published var currentTime: TimeInterval = 0

    // Store the URL for comparison purposes
    let url: URL

    private var cancellables = Set<AnyCancellable>()
    private var timeObserver: Any?

    init(url: URL) {
        // Store the URL
        self.url = url

        // Create AVPlayerItem for better control
        let playerItem = AVPlayerItem(url: url)

        // Configure player item for optimal video playback
        playerItem.preferredForwardBufferDuration = 2.0  // Reduced from 5.0 for faster start
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        // Create player with the configured item
        self.player = AVPlayer(playerItem: playerItem)

        // Configure player for optimal performance
        player.automaticallyWaitsToMinimizeStalling = false  // Don't wait - start immediately
        player.allowsExternalPlayback = true

        // Setup observers asynchronously to avoid blocking initialization
        DispatchQueue.main.async { [weak self] in
            self?.observeTimeControlStatus()
            self?.observePlayerItemStatus()
        }
    }

    // Handle video play/pause
    func togglePlay() {
        if isFinishedPlaying {
            isFinishedPlaying = false
            player.seek(to: .zero)
            progress = 0
            lastDraggedProgress = 0
        }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }

        timeoutControls()
    }

    // Handles timeout for controls visibility
    func timeoutControls() {
        if let timeoutTask {
            timeoutTask.cancel()
        }

        // Don't set timeout if video is paused - keep controls visible
        guard isPlaying else { return }

        timeoutTask = .init(block: {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.showPlayerControls = false
            }
        })

        if let timeoutTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeoutTask)
        }
    }

    // Video player time observer setup
    func addTimeObserver() {
        guard !isObserverAdded else { return }

        // Use different intervals based on player mode for performance
        let interval = isInMiniPlayerMode ? 2.0 : 1.0  // Less frequent updates in mini player

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            guard let self = self, let currentPlayerItem = self.player.currentItem else { return }

            let totalDuration = currentPlayerItem.duration.seconds
            let currentDuration = self.player.currentTime().seconds

            let calculatedProgress = currentDuration / totalDuration
            if !self.isSeeking {
                self.progress = calculatedProgress
                self.lastDraggedProgress = self.progress
            }

            // Update published currentTime for UI binding
            self.currentTime = currentDuration

            if calculatedProgress >= 1 {
                self.isFinishedPlaying = true
                self.isPlaying = false
            }
        }

        isObserverAdded = true

        self.playerStatusObserver = self.player.observe(
            \.status,
            options: .new
        ) { player, _ in
            if player.status == .readyToPlay {
                self.generateThumbnailFrames()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.videoDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: self.player.currentItem
        )

        self.timeoutTask?.cancel()
    }

    // Remove time observer for cleanup
    func removeTimeObserver() {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        isObserverAdded = false
    }

    func togglePlayWithAnimation(isPlaying: Bool, duration: Double = 0.15) {
        withAnimation(.easeInOut(duration: duration)) {
            self.isPlaying.toggle()
        }
    }

    // Seek functionality with thumbnails
    func seek(to progress: CGFloat) {
        guard let currentPlayerItem = player.currentItem else { return }
        let totalDuration = currentPlayerItem.duration.seconds
        player.seek(to: .init(seconds: totalDuration * Double(progress), preferredTimescale: 600))
        lastDraggedProgress = progress
    }

    // Generate thumbnail frames for seeking
    func generateThumbnailFrames() {
        Task {
            guard let asset = player.currentItem?.asset else { return }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 250, height: 250)

            do {
                let totalDuration = try await asset.load(.duration).seconds
                var frameTimes: [CMTime] = []

                for progress in stride(from: 0, to: 1, by: 0.01) {
                    let time = CMTime(seconds: progress * totalDuration, preferredTimescale: 600)
                    frameTimes.append(time)
                }

                for try await result in generator.images(for: frameTimes) {
                    let cgImage = try result.image
                    await MainActor.run {
                        self.thumbnailFrames.append(UIImage(cgImage: cgImage))
                    }
                }
            } catch {
                print("Error generating thumbnail frames: \(error.localizedDescription)")
            }
        }
    }

    @objc func videoDidFinishPlaying() {
        // Handle video finish logic here
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isFinishedPlaying = true
        }
    }

    // MARK: - Performance Optimization Methods

    func setMiniPlayerMode(_ isMini: Bool) {
        isInMiniPlayerMode = isMini
        shouldOptimizeForMiniPlayer = isMini

        if isMini {
            optimizeForMiniPlayer()
        } else {
            optimizeForFullscreen()
        }
    }

    private func optimizeForMiniPlayer() {
        // Reduce quality for better performance
        if let currentItem = player.currentItem {
            currentItem.preferredPeakBitRate = 500_000  // 500 kbps
        }

        // Reduce thumbnail generation frequency
        if thumbnailFrames.count > 50 {
            thumbnailFrames = Array(thumbnailFrames.prefix(50))
        }
    }

    private func optimizeForFullscreen() {
        // Higher quality for fullscreen
        if let currentItem = player.currentItem {
            currentItem.preferredPeakBitRate = 2_000_000  // 2 Mbps
        }
    }

    // Detect video size and aspect ratio
    func detectVideoSize() {
        guard let item = player.currentItem else { return }
        let size = item.presentationSize
        if size.width > 0 && size.height > 0 {
            detectedVideoSize = size
        }
    }

    // Cleanup method for proper resource management
    func cleanup() {
        removeTimeObserver()
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        player.pause()
        cancellables.removeAll()
    }

    private func observeTimeControlStatus() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }

                let loading = (status == .waitingToPlayAtSpecifiedRate)
                self.isLoading = loading

                // Sync isPlaying state with actual player state
                let actuallyPlaying = (status == .playing)
                if self.isPlaying != actuallyPlaying {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.isPlaying = actuallyPlaying
                    }
                }

                withAnimation(.easeInOut(duration: 0.15)) {
                    self.showPlayerControls = loading
                }

                // Check if playback fails
                if status == .paused, let error = self.player.currentItem?.error {
                    print("Playback error: \(error.localizedDescription)")
                    self.playerError = true
                }
            }
            .store(in: &cancellables)
    }

    private func observePlayerItemStatus() {
        player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playerItem in
                guard let self = self, let item = playerItem else { return }

                // Observe player item status changes
                item.publisher(for: \.status)
                    .receive(on: DispatchQueue.main)
                    .sink { status in
                        switch status {
                        case .readyToPlay:
                            self.isLoading = false
                            self.playerError = false
                            // Detect video size when ready
                            self.detectVideoSize()
                        case .failed:
                            self.isLoading = false
                            self.playerError = true
                            if let error = item.error {
                                print("Player item error: \(error.localizedDescription)")
                            }
                        case .unknown:
                            self.isLoading = true
                        @unknown default:
                            break
                        }
                    }
                    .store(in: &self.cancellables)
            }
            .store(in: &cancellables)
    }
}
