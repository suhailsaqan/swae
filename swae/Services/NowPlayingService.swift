//
//  NowPlayingService.swift
//  swae
//
//  Manages MPNowPlayingInfoCenter and MPRemoteCommandCenter
//  for lock screen / Control Center media controls.
//

import AVFoundation
import Combine
import MediaPlayer
import UIKit

final class NowPlayingService {
    static let shared = NowPlayingService()

    private var player: VideoPlayer?
    private var liveStream: LiveStream?
    private var timeObserver: Any?
    private var playbackStateCancellable: AnyCancellable?

    private init() {}

    // MARK: - Public API

    /// Call when the user starts watching a stream or recording.
    func activate(player: VideoPlayer, liveStream: LiveStream) {
        // Clean up previous observers if re-activating (e.g. re-expand from mini player)
        removePeriodicTimeObserver()
        playbackStateCancellable?.cancel()
        teardownRemoteCommands()

        self.player = player
        self.liveStream = liveStream

        // Required for the app to receive remote control events (lock screen, Control Center)
        UIApplication.shared.beginReceivingRemoteControlEvents()

        setupRemoteCommands()
        observePlaybackState()
        addPeriodicTimeObserver()
        loadArtwork(from: liveStream.thumbnailURL)

        // Defer the initial nowPlayingInfo update until the player is actually
        // producing audio. iOS ignores Now Playing metadata when no audio is flowing.
        if player.isPlaying {
            updateNowPlayingInfo()
        }
    }

    /// Call when the player is fully dismissed (not mini-player).
    func deactivate() {
        removePeriodicTimeObserver()
        playbackStateCancellable?.cancel()
        playbackStateCancellable = nil
        teardownRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        UIApplication.shared.endReceivingRemoteControlEvents()
        player = nil
        liveStream = nil
    }

    /// Call when stream metadata changes (e.g. viewer count, title).
    func updateMetadata(liveStream: LiveStream) {
        self.liveStream = liveStream
        updateNowPlayingInfo()
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let player = self.player else { return .commandFailed }
            if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
            return .success
        }

        // Skip forward/backward for recordings only
        if let player, !player.isLive {
            commandCenter.skipForwardCommand.isEnabled = true
            commandCenter.skipForwardCommand.preferredIntervals = [15]
            commandCenter.skipForwardCommand.addTarget { [weak self] event in
                guard let self, let player = self.player,
                      let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
                let currentTime = player.avPlayer.currentTime()
                let newTime = CMTimeAdd(currentTime, CMTime(seconds: event.interval, preferredTimescale: 600))
                player.avPlayer.seek(to: newTime)
                return .success
            }

            commandCenter.skipBackwardCommand.isEnabled = true
            commandCenter.skipBackwardCommand.preferredIntervals = [15]
            commandCenter.skipBackwardCommand.addTarget { [weak self] event in
                guard let self, let player = self.player,
                      let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
                let currentTime = player.avPlayer.currentTime()
                let newTime = CMTimeSubtract(currentTime, CMTime(seconds: event.interval, preferredTimescale: 600))
                player.avPlayer.seek(to: newTime)
                return .success
            }
        }
    }

    private func teardownRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let liveStream, let player else { return }

        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = liveStream.title
        info[MPMediaItemPropertyArtist] = liveStream.streamerName
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.isPlaying ? 1.0 : 0.0

        if liveStream.isLive {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        } else {
            // Recording: include duration and elapsed time
            if let duration = player.avPlayer.currentItem?.duration,
               duration.isNumeric && !duration.isIndefinite {
                info[MPMediaItemPropertyPlaybackDuration] = duration.seconds
            }
            let elapsed = player.avPlayer.currentTime().seconds
            if elapsed.isFinite && elapsed >= 0 {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Periodic Time Observer (for recording elapsed time)

    private func addPeriodicTimeObserver() {
        guard let player else { return }

        // For recordings: update elapsed time every second.
        // For live streams: update every 5 seconds to keep Now Playing info fresh.
        let interval = player.isLive ? 5.0 : 1.0

        timeObserver = player.avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.updateNowPlayingInfo()
        }
    }

    private func removePeriodicTimeObserver() {
        if let timeObserver, let player {
            player.avPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    // MARK: - Playback State Observation

    private func observePlaybackState() {
        playbackStateCancellable = player?.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
    }

    // MARK: - Artwork Loading

    private func loadArtwork(from url: URL?) {
        guard let url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

            DispatchQueue.main.async {
                guard self?.liveStream != nil else { return }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }.resume()
    }
}
