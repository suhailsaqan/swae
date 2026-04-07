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
        item.preferredForwardBufferDuration = 2.0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        avPlayer.replaceCurrentItem(with: item)
        self.url = url.absoluteString
        applyPreferredQuality()
        play()
        parseHLSQualities(from: url)
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

    /// The currently selected quality tier. nil = Auto (let AVPlayer decide).
    var preferredQuality: HLSQualityTier? {
        didSet {
            applyPreferredQuality()
        }
    }

    /// Available quality tiers parsed from the HLS manifest. Empty for non-HLS streams.
    @Published private(set) var availableQualities: [HLSQualityTier] = []

    private func playerWithURL(_ url: String) -> AVPlayer {
        guard let url = URL(string: url) else { return AVPlayer() }

        let item = AVPlayerItem(url: url)
        // Smaller forward buffer for faster initial playback start
        item.preferredForwardBufferDuration = 2.0
        // Allow network use while paused so resume is instant
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        let player = AVPlayer(playerItem: item)
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        didInitPlayer = true

        // Parse available HLS quality variants
        parseHLSQualities(from: url)

        return player
    }

    private func applyPreferredQuality() {
        if let tier = preferredQuality {
            avPlayer.currentItem?.preferredPeakBitRate = Double(tier.bandwidth)
        } else {
            // Auto — no limit, let AVPlayer adapt
            avPlayer.currentItem?.preferredPeakBitRate = 0
        }
    }

    private func parseHLSQualities(from url: URL) {
        let urlString = url.absoluteString.lowercased()
        guard urlString.contains("m3u8") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .returnCacheDataElseLoad

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data, error == nil,
                  let manifest = String(data: data, encoding: .utf8) else { return }

            var tiers: [HLSQualityTier] = []
            let lines = manifest.components(separatedBy: .newlines)

            for line in lines {
                guard line.hasPrefix("#EXT-X-STREAM-INF") else { continue }

                var bandwidth: Int?
                var width: Int?
                var height: Int?

                // Parse BANDWIDTH
                if let bwRange = line.range(of: "BANDWIDTH=") {
                    let afterBw = line[bwRange.upperBound...]
                    let bwStr = afterBw.prefix(while: { $0.isNumber })
                    bandwidth = Int(bwStr)
                }

                // Parse RESOLUTION
                if let resRange = line.range(of: "RESOLUTION=") {
                    let afterRes = line[resRange.upperBound...]
                    let resStr = afterRes.prefix(while: { $0 != "," && $0 != "\n" && $0 != " " })
                    let parts = resStr.split(separator: "x")
                    if parts.count == 2 {
                        width = Int(parts[0])
                        height = Int(parts[1])
                    }
                }

                if let bw = bandwidth, let w = width, let h = height, w > 0, h > 0 {
                    tiers.append(HLSQualityTier(width: w, height: h, bandwidth: bw))
                }
            }

            // Sort by resolution descending (highest first)
            tiers.sort { ($0.width * $0.height) > ($1.width * $1.height) }

            // Deduplicate by resolution label (some manifests have duplicate resolutions)
            var seen = Set<String>()
            tiers = tiers.filter { seen.insert($0.label).inserted }

            DispatchQueue.main.async {
                self?.availableQualities = tiers
            }
        }.resume()
    }
}

/// Represents a single HLS quality variant.
struct HLSQualityTier: Identifiable, Equatable {
    let width: Int
    let height: Int
    let bandwidth: Int

    var id: String { label }

    /// Human-readable label like "1080p", "720p", etc.
    var label: String {
        // Use the larger dimension for the label (e.g. 1920x1080 → "1080p", 1080x1920 → "1080p")
        let p = max(width, height) == width ? height : width
        // For standard landscape, height is the label. For portrait, width is.
        return "\(min(width, height))p"
    }

    /// Formatted bandwidth string like "2.5 Mbps"
    var bandwidthLabel: String {
        let mbps = Double(bandwidth) / 1_000_000
        if mbps >= 1 {
            return String(format: "%.1f Mbps", mbps)
        } else {
            return "\(bandwidth / 1000) kbps"
        }
    }
}



