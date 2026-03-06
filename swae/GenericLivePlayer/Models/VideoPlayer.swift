//
//  VideoPlayer.swift
//  swae
//
//  Video player wrapper for managing playback state
//

import AVFoundation
import Combine
import Foundation

/// Represents the current playback state of the video player
enum PlaybackState {
    case playing
    case paused
    case loading  // Buffering or waiting to play
}

class VideoPlayer: NSObject {
    var didInitPlayer = false

    private var looper: AVPlayerLooper?
    lazy var avPlayer: AVPlayer = playerWithURL(url)

    /// Current playback state - always reflects actual AVPlayer state
    @Published private(set) var playbackState: PlaybackState = .paused

    /// Whether the recording has finished playing (reached end of file)
    @Published private(set) var didFinishPlaying: Bool = false
    
    /// Convenience property for checking if currently playing
    var isPlaying: Bool { playbackState == .playing }

    var shouldPause = false

    var url: String
    var userPubkey: String
    var originalURL: String

    var liveStream: LiveStream?
    var isLive: Bool { liveStream != nil }
    
    /// Cancellable for AVPlayer state observation
    private var statusCancellable: AnyCancellable?

    /// Observer for end-of-recording notification
    private var endOfPlaybackObserver: NSObjectProtocol?

    init(
        url: String, originalURL: String = "", userPubkey: String = "",
        liveStream: LiveStream? = nil
    ) {
        self.url = url
        self.originalURL = originalURL.isEmpty ? url : originalURL
        self.userPubkey = userPubkey
        self.liveStream = liveStream
        super.init()
        
        // Setup observation after avPlayer is created (lazy var triggers creation)
        setupStateObservation()
        setupEndOfPlaybackObserver()
    }

    deinit {
        statusCancellable?.cancel()
        if let observer = endOfPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Observe actual AVPlayer timeControlStatus to update playbackState
    private func setupStateObservation() {
        statusCancellable = avPlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                
                switch status {
                case .playing:
                    self.playbackState = .playing
                case .paused:
                    self.playbackState = .paused
                case .waitingToPlayAtSpecifiedRate:
                    self.playbackState = .loading
                @unknown default:
                    self.playbackState = .paused
                }
            }
    }

    func play() {
        shouldPause = false
        avPlayer.play()
        // playbackState will be updated by timeControlStatus observer
    }

    func pause() {
        shouldPause = false
        avPlayer.pause()
        // playbackState will be updated by timeControlStatus observer
    }

    /// Replays from the beginning after a recording has finished
    func replay() {
        didFinishPlaying = false
        avPlayer.seek(to: .zero) { [weak self] _ in
            self?.play()
        }
    }

    /// Clears the finished flag without seeking or playing (e.g., when user scrubs to a new position)
    func clearFinishedFlag() {
        didFinishPlaying = false
    }

    /// Switches the player to a new URL (e.g., live stream → recording)
    func switchToURL(_ url: URL) {
        didFinishPlaying = false
        let item = AVPlayerItem(url: url)
        avPlayer.replaceCurrentItem(with: item)
        self.url = url.absoluteString
        play()
    }

    func delayedPause() {
        shouldPause = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) {
            if self.shouldPause {
                self.pause()
            }
        }
    }

    /// Observe AVPlayerItemDidPlayToEndTime to detect when a recording finishes
    private func setupEndOfPlaybackObserver() {
        endOfPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let finishedItem = notification.object as? AVPlayerItem,
                  finishedItem == self.avPlayer.currentItem else { return }
            self.didFinishPlaying = true
            self.playbackState = .paused
        }
    }

    private func playerWithURL(_ url: String) -> AVPlayer {
        guard let url = URL(string: url) else { return AVPlayer() }

        if isLive {
            let player = AVPlayer(url: url)
            player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
            return player
        }

        let queuePlayer = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        didInitPlayer = true
        queuePlayer.isMuted = true
        return queuePlayer
    }
}



