//
//  LiveStreamModels.swift
//  swae
//
//  Data models for the generic live player
//

import AVFoundation
import Foundation
import UIKit

struct LiveStream {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let videoURL: URL?
    let isLive: Bool
    let viewerCount: Int
    let startDate: Date
    let streamerName: String
    let streamerAvatarURL: URL?
    let status: String

    // Recording metadata (Phase 1)
    let hasRecording: Bool
    let recordingURL: URL?
    let streamingURL: URL?

    init(
        id: String,
        title: String,
        thumbnailURL: URL?,
        videoURL: URL?,
        isLive: Bool = true,
        viewerCount: Int = 0,
        startDate: Date = Date(),
        streamerName: String,
        streamerAvatarURL: URL?,
        status: String = "live",
        hasRecording: Bool = false,
        recordingURL: URL? = nil,
        streamingURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.videoURL = videoURL
        self.isLive = isLive
        self.viewerCount = viewerCount
        self.startDate = startDate
        self.streamerName = streamerName
        self.streamerAvatarURL = streamerAvatarURL
        self.status = status
        self.hasRecording = hasRecording
        self.recordingURL = recordingURL
        self.streamingURL = streamingURL
    }

    var startedText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeTime = formatter.localizedString(for: startDate, relativeTo: Date())

        if isLive {
            return "Started \(relativeTime)"
        }
        return "Streamed \(relativeTime)"
    }
}

class LiveChatMessage {
    let id: String
    let userName: String
    let text: String
    let timestamp: Date

    init(id: String, userName: String, text: String, timestamp: Date = Date()) {
        self.id = id
        self.userName = userName
        self.text = text
        self.timestamp = timestamp
    }
}

// MARK: - PlayerView (Simple AVPlayerLayer wrapper)
final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    init() {
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
