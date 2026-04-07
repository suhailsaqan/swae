import AVFoundation
import Combine
import Foundation
import SwiftUI
import VideoToolbox

private let lowPowerBitrate: UInt32 = 2_000_000

private let iAmLiveWebhookUrl =
    URL(
        string: """
            https://discord.com/api/webhooks/1383532422573985822/\
            jI3eX5CLADDvhWa93guXttqHCZ_uOalfsYQi2AeYcu6IhFSFw1StNIWPTKTIuFzrWn-q
            """
    )!
let fffffMessage = String(localized: "😢 FFFFF 😢")
let lowBitrateMessage = String(localized: "Low bitrate")
let lowBatteryMessage = String(localized: "Low battery")

class CreateStreamWizard: ObservableObject {
    var platform: WizardPlatform = .custom
    var networkSetup: WizardNetworkSetup = .none
    var customProtocol: WizardCustomProtocol = .none
    let twitchStream = SettingsStream(name: "")
    var twitchAccessToken = ""
    var twitchLoggedIn: Bool = false
    @Published var isPresenting = false
    @Published var isPresentingSetup = false
    @Published var showTwitchAuth = false
    @Published var name = ""
    @Published var twitchChannelName = ""
    @Published var twitchChannelId = ""
    @Published var kickChannelName = ""
    @Published var youTubeHandle = ""
    @Published var afreecaTvChannelName = ""
    @Published var afreecaTvStreamId = ""
    @Published var obsAddress = ""
    @Published var obsPort = ""
    @Published var obsRemoteControlEnabled = false
    @Published var obsRemoteControlUrl = ""
    @Published var obsRemoteControlPassword = ""
    @Published var obsRemoteControlSourceName = ""
    @Published var obsRemoteControlBrbScene = ""
    @Published var directIngest = ""
    @Published var directStreamKey = ""
    @Published var chatBttv = false
    @Published var chatFfz = false
    @Published var chatSeventv = false
    @Published var belaboxUrl = ""
    @Published var zapStreamCoreStreamTitle = ""
    @Published var zapStreamCoreStreamDescription = ""
    @Published var zapStreamCoreIsPublic = true
    @Published var zapStreamCoreStreamImage = ""
    @Published var zapStreamCoreStreamTags: [String] = []
    @Published var zapStreamCoreContentWarning = ""
    @Published var customSrtUrl = ""
    @Published var customSrtStreamId = ""
    @Published var customRtmpUrl = ""
    @Published var customRtmpStreamKey = ""
    @Published var customRistUrl = ""
}

enum StreamState {
    case connecting
    case connected
    case disconnected
}

func failedToConnectMessage(_ name: String) -> String {
    return String(localized: "😢 Failed to connect to \(name) 😢")
}

extension Model {
    func startStream(delayed: Bool = false) {
        logger.info("stream: Start")
        guard !streaming else {
            return
        }
        if delayed, !isLive {
            return
        }

        // Check if zap-stream-core is enabled and configured
        if stream.zapStreamCoreEnabled {
            // Prevent streaming without a signed-in user
            guard appState?.publicKey != nil else {
                makeErrorToast(
                    title: String(localized: "Sign In Required"),
                    subTitle: String(localized: "Please sign in to stream with zap.stream.")
                )
                return
            }
            startZapStreamCoreStream(delayed: delayed)
            return
        }

        guard stream.url != defaultStreamUrl else {
            makeErrorToast(
                title: String(
                    localized: "Please enter your stream URL in stream settings before going live."
                ),
                subTitle: String(
                    localized: "Configure it in Settings → Streams → \(stream.name) → URL."
                )
            )
            return
        }
        if database.location.resetWhenGoingLive {
            resetLocationData()
        }
        streamLog.removeAll()
        setIsLive(value: true)
        streaming = true
        streamTotalBytes = 0
        streamTotalChatMessages = 0
        updateScreenAutoOff()
        startNetStream()
        startFetchingYouTubeChatVideoId()
        if stream.recording.autoStartRecording {
            startRecording()
        }
        if stream.obsAutoStartStream {
            obsStartStream()
        }
        if stream.obsAutoStartRecording {
            obsStartRecording()
        }
        streamingHistoryStream = StreamingHistoryStream(settings: stream.clone())
        streamingHistoryStream!.updateHighestThermalState(
            thermalState: ThermalState(from: statusOther.thermalState))
        streamingHistoryStream!.updateLowestBatteryLevel(level: battery.level)
    }

    func stopStream(stopObsStreamIfEnabled: Bool = true, stopObsRecordingIfEnabled: Bool = true)
        -> Bool
    {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        setIsLive(value: false)
        updateScreenAutoOff()
        realtimeIrl?.stop()
        stopFetchingYouTubeChatVideoId()
        if !streaming {
            return false
        }
        logger.info("stream: Stop")

        // Unsubscribe from own live event when stopping a zap-stream-core stream
        if stream.zapStreamCoreEnabled {
            appState?.unsubscribeFromOwnLiveEvent()
            stopZapStreamMetrics()
        }

        streamTotalBytes += UInt64(media.streamTotal())
        streaming = false
        if stream.recording.autoStopRecording {
            stopRecording()
        }
        if stopObsStreamIfEnabled, stream.obsAutoStopStream {
            obsStopStream()
        }
        if stopObsRecordingIfEnabled, stream.obsAutoStopRecording {
            obsStopRecording()
        }
        stopNetStream()
        makeStreamEndedToast()
        streamState = .disconnected
        if let streamingHistoryStream {
            if let logId = streamingHistoryStream.logId {
                logsStorage.write(id: logId, data: streamLog.joined(separator: "\n").utf8Data)
            }
            streamingHistoryStream.stopTime = Date()
            streamingHistoryStream.totalBytes = streamTotalBytes
            streamingHistoryStream.numberOfChatMessages = streamTotalChatMessages
            streamingHistory.append(stream: streamingHistoryStream)
            streamingHistory.store()
        }
        return true
    }

    func isGoLiveNotificationConfigured() -> Bool {
        guard !stream.goLiveNotificationDiscordMessage.isEmpty else {
            return false
        }
        guard !stream.goLiveNotificationDiscordWebhookUrl.isEmpty else {
            return false
        }
        return true
    }

    func sendGoLiveNotification() {
        media.takeSnapshot(age: 0.0) { image, _, _ in
            guard let imageJpeg = image.jpegData(compressionQuality: 0.9) else {
                return
            }
            DispatchQueue.main.async {
                if let url = URL(string: self.stream.goLiveNotificationDiscordWebhookUrl) {
                    self.tryUploadGoLiveNotificationToDiscord(imageJpeg, url)
                }
            }
        }
    }

    private func tryUploadGoLiveNotificationToDiscord(_ image: Data, _ url: URL) {
        uploadImage(
            url: url,
            paramName: "snapshot",
            fileName: "snapshot.jpg",
            image: image,
            message: stream.goLiveNotificationDiscordMessage
        ) { _ in }
    }

    private func startNetStream() {
        streamState = .connecting
        latestLowBitrateTime = .now
        moblink.streamer?.stopTunnels()

        // Backstop timeout: if we're still .connecting after 20s, something is stuck.
        // Normal failures are handled by onDisconnected + max retry.
        // This catches edge cases where the socket never reports failure.
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: 20.0, repeats: false
        ) { [weak self] _ in
            guard let self, self.streaming, self.streamState == .connecting else { return }
            logger.warning("stream: Connection timed out (backstop)")
            self.makeErrorToast(
                title: String(localized: "Connection Timed Out"),
                subTitle: String(
                    localized: "Could not reach the server. Check your connection and try again."
                ),
                vibrate: true
            )
            _ = self.stopStream()
        }

        if stream.twitchMultiTrackEnabled {
            startNetStreamMultiTrack()
        } else {
            startNetStreamSingleTrack()
        }
    }

    private func startNetStreamMultiTrack() {
        twitchMultiTrackGetClientConfiguration(
            url: stream.url,
            dimensions: stream.dimensions(),
            fps: stream.fps
        ) { response in
            DispatchQueue.main.async {
                self.startNetStreamMultiTrackCompletion(response: response)
            }
        }
    }

    private func startNetStreamMultiTrackCompletion(
        response: TwitchMultiTrackGetClientConfigurationResponse?
    ) {
        guard let response else {
            return
        }
        guard let ingestEndpoint = response.ingest_endpoints.first(where: { $0.proto == "RTMP" })
        else {
            return
        }
        let url = ingestEndpoint.url_template.replacingOccurrences(
            of: "{stream_key}",
            with: ingestEndpoint.authentication
        )
        guard
            let videoEncoderSettings = createMultiTrackVideoCodecSettings(
                encoderConfigurations: response
                    .encoder_configurations)
        else {
            return
        }
        media.rtmpMultiTrackStartStream(url, videoEncoderSettings)
        updateSpeed(now: .now)
    }

    private func createMultiTrackVideoCodecSettings(
        encoderConfigurations: [TwitchMultiTrackGetClientConfigurationEncoderContiguration]
    )
        -> [VideoEncoderSettings]?
    {
        var videoEncoderSettings: [VideoEncoderSettings] = []
        for encoderConfiguration in encoderConfigurations {
            var settings = VideoEncoderSettings()
            let bitrate = encoderConfiguration.settings.bitrate
            guard bitrate >= 100, bitrate <= 50000 else {
                return nil
            }
            settings.bitRate = bitrate * 1000
            let width = encoderConfiguration.width
            let height = encoderConfiguration.height
            guard width >= 1, width <= 5000 else {
                return nil
            }
            guard height >= 1, height <= 5000 else {
                return nil
            }
            settings.videoSize = CMVideoDimensions(width: width, height: height)
            settings.maxKeyFrameIntervalDuration = encoderConfiguration.settings.keyint_sec
            settings.allowFrameReordering = encoderConfiguration.settings.bframes
            let codec = encoderConfiguration.type
            let profile = encoderConfiguration.settings.profile
            if codec.hasSuffix("avc"), profile == "main" {
                settings.profileLevel = kVTProfileLevel_H264_Main_AutoLevel as String
            } else if codec.hasSuffix("avc"), profile == "high" {
                settings.profileLevel = kVTProfileLevel_H264_High_AutoLevel as String
            } else if codec.hasSuffix("hevc"), profile == "main" {
                settings.profileLevel = kVTProfileLevel_HEVC_Main_AutoLevel as String
            } else {
                logger.error(
                    "Unsupported multi track codec and profile combination: \(codec) \(profile)")
                return nil
            }
            videoEncoderSettings.append(settings)
        }
        return videoEncoderSettings
    }

    private func startNetStreamSingleTrack() {
        switch stream.getProtocol() {
        case .rtmp:
            media.rtmpStartStream(
                url: stream.url,
                targetBitrate: getBitrate(),
                adaptiveBitrate: stream.rtmp.adaptiveBitrateEnabled)
            updateAdaptiveBitrateRtmpIfEnabled()
        case .srt:
            payloadSize = stream.srt.mpegtsPacketsPerPacket * MpegTsPacket.size
            media.srtStartStream(
                isSrtla: stream.isSrtla(),
                url: stream.url,
                reconnectTime: 5,
                targetBitrate: getBitrate(),
                adaptiveBitrateAlgorithm: stream.srt.adaptiveBitrateEnabled!
                    ? stream.srt.adaptiveBitrate!.algorithm
                    : nil,
                latency: stream.srt.latency,
                overheadBandwidth: database.debug.srtOverheadBandwidth,
                maximumBandwidthFollowInput: database.debug.maximumBandwidthFollowInput,
                mpegtsPacketsPerPacket: stream.srt.mpegtsPacketsPerPacket,
                networkInterfaceNames: database.networkInterfaceNames,
                connectionPriorities: stream.srt.connectionPriorities!,
                dnsLookupStrategy: stream.srt.dnsLookupStrategy!
            )
            updateAdaptiveBitrateSrt(stream: stream)
        case .rist:
            media.ristStartStream(
                url: stream.url,
                bonding: stream.rist.bonding,
                targetBitrate: getBitrate(),
                adaptiveBitrate: stream.rist.adaptiveBitrateEnabled)
            updateAdaptiveBitrateRistIfEnabled()
        }
        updateSpeed(now: .now)
    }

    private func stopNetStream() {
        moblink.streamer?.stopTunnels()
        reconnectTimer.stop()
        media.rtmpStopStream()
        media.srtStopStream()
        media.ristStopStream()
        streamStartTime = nil
        updateStreamUptime(now: .now)
        updateSpeed(now: .now)
        updateAudioLevel()
        bonding.statistics = noValue
    }

    func setCurrentStream(stream: SettingsStream) {
        self.stream = stream
        stream.enabled = true
        for ostream in database.streams where ostream.id != stream.id {
            ostream.enabled = false
        }
        currentStreamId = stream.id
        updateOrientationLock()
        updateStatusStreamText()
    }

    func setCurrentStream(streamId: UUID) -> Bool {
        guard let stream = findStream(id: streamId) else {
            return false
        }
        setCurrentStream(stream: stream)
        return true
    }

    func setCurrentStream() {
        let profileStreams = streamsForCurrentProfile
        setCurrentStream(stream: profileStreams.first(where: { $0.enabled })
                         ?? profileStreams.first
                         ?? fallbackStream)
    }

    /// Returns streams owned by the current profile, or legacy unowned streams.
    var streamsForCurrentProfile: [SettingsStream] {
        let currentPubkey = appState?.publicKey?.hex
        return database.streams.filter { stream in
            stream.ownerPublicKeyHex == currentPubkey || stream.ownerPublicKeyHex == nil
        }
    }

    func findStream(id: UUID) -> SettingsStream? {
        return database.streams.first { stream in
            stream.id == id
        }
    }

    // MARK: - Profile Switch Stream Reset

    /// Tears down all streaming state and re-initializes for the new user profile.
    /// Called via NotificationCenter when the active Nostr profile changes.
    func resetStreamStateForProfileSwitch() {
        logger.info("stream: Resetting stream state for profile switch")

        // 1. Stop any active stream (prevents streaming on wrong account)
        if streaming {
            _ = stopStream()
        }

        // 2. Tear down zap-stream-core API client and stream session
        zapStreamCoreApiClient = nil
        zapStreamCoreStream = nil

        // 3. Clear cached zap-stream-core account state
        zapStreamCoreBalance = nil
        zapStreamCoreRate = 0
        zapStreamCoreHasNwc = false
        zapStreamCoreTosAccepted = false
        zapStreamCoreTosLink = nil

        // 4. Stop balance polling
        stopBalancePolling()
        balanceRefreshCancellable?.cancel()
        balanceRefreshCancellable = nil

        // 5. Tear down metrics WebSocket
        stopZapStreamMetrics()

        // 6. Stop nostr chat bridge
        stopNostrChatBridge()

        // 7. Unsubscribe from own live event
        appState?.unsubscribeFromOwnLiveEvent()

        // 8. Re-select the correct stream for the new profile
        setCurrentStream()

        // 9. Clear cached URL/key on the newly selected stream if it uses zap-stream-core.
        //    This forces re-fetch from API on next "Go Live" so the correct user's
        //    ingest endpoint is used.
        if stream.zapStreamCoreEnabled {
            stream.url = defaultStreamUrl
            stream.zapStreamCoreStreamKey = ""
        }

        // 10. Re-initialize zap-stream-core if the new stream uses it
        setupZapStreamCore()

        // 11. Reload the stream pipeline (codecs, resolution, etc.)
        reloadStream()

        // 12. Persist immediately so cleared URL survives app crash
        store()

        // 13. Proactively fetch the new user's account info
        refreshZapStreamCoreBalance()

        logger.info("stream: Profile switch reset complete")
    }

    func reloadStream() {
        cameraPosition = nil
        stopRecorderIfNeeded(forceStop: true)
        _ = stopStream()
        setNetStream()
        setStreamResolution()
        setStreamFps()
        setColorSpace()
        setStreamCodec()
        setStreamAdaptiveResolution()
        setStreamKeyFrameInterval()
        setStreamBitrate(stream: stream)
        setAudioStreamBitrate(stream: stream)
        setAudioStreamFormat(format: .aac)
        setAudioChannelsMap(channelsMap: [
            0: database.audio.audioOutputToInputChannelsMap!.channel1,
            1: database.audio.audioOutputToInputChannelsMap!.channel2,
        ])
        startRecorderIfNeeded()
        reloadConnections()
        resetChat()
        reloadLocation()
        reloadRtmpStreams()
        updateStatusStreamText()
        // Re-establish WebRTC frame bridge if a collab call is active.
        // setNetStream() creates a new Processor, which replaces the VideoUnit
        // that had onRawFrameCaptured set. Without this, the WebRTC video freezes.
        reestablishCollabBridgeIfNeeded()
    }

    func reloadStreamIfEnabled(stream: SettingsStream) {
        if stream.enabled {
            reloadStream()
            resetSelectedScene(changeScene: false)
            updateOrientation()
        }
    }

    private func setNetStream() {
        cameraPreviewLayer?.session = nil
        media.setNetStream(
            proto: stream.getProtocol(),
            portrait: stream.portrait,
            timecodesEnabled: isTimecodesEnabled(),
            builtinAudioDelay: database.debug.builtinAudioAndVideoDelay,
            destinations: stream.multiStreaming.destinations,
            newSrt: database.debug.newSrt
        )
        updateTorch()
        updateMute()
        attachStream()
        setLowFpsImage()
        setSceneSwitchTransition()
        setCleanSnapshots()
        setCleanRecordings()
        setCleanExternalDisplay()
        updateCameraControls()
    }

    private func attachStream() {
        guard let processor = media.getProcessor() else {
            processor = nil
            return
        }
        processorControlQueue.async {
            processor.setDrawable(drawable: self.streamPreviewView)
            processor.setExternalDisplayDrawable(drawable: self.externalDisplayStreamPreviewView)
            self.processor = processor
            processor.startRunning()
        }
    }

    func setStreamResolution(resolution: SettingsStreamResolution? = nil) {
        var captureSize: CGSize
        var outputSize: CGSize
        switch resolution ?? stream.resolution {
        case .r3840x2160:
            captureSize = .init(width: 3840, height: 2160)
            outputSize = .init(width: 3840, height: 2160)
        case .r2560x1440:
            // Use 4K camera and downscale to 1440p.
            captureSize = .init(width: 3840, height: 2160)
            outputSize = .init(width: 2560, height: 1440)
        case .r1920x1080:
            captureSize = .init(width: 1920, height: 1080)
            outputSize = .init(width: 1920, height: 1080)
        case .r1280x720:
            captureSize = .init(width: 1280, height: 720)
            outputSize = .init(width: 1280, height: 720)
        case .r960x540:
            captureSize = .init(width: 960, height: 540)
            outputSize = .init(width: 960, height: 540)
        case .r854x480:
            // Use 540p camera and downscale to 480p.
            captureSize = .init(width: 960, height: 540)
            outputSize = .init(width: 854, height: 480)
        case .r640x360:
            // Use 540p camera and downscale to 360p.
            captureSize = .init(width: 960, height: 540)
            outputSize = .init(width: 640, height: 360)
        case .r426x240:
            // Use 540p camera and downscale to 240p.
            captureSize = .init(width: 960, height: 540)
            outputSize = .init(width: 426, height: 240)
        }
        if stream.portrait {
            outputSize = .init(width: outputSize.height, height: outputSize.width)
        }
        media.setVideoSize(capture: captureSize, output: outputSize)
    }

    private func setStreamCodec() {
        switch stream.codec {
        case .h264avc:
            media.setVideoProfile(profile: kVTProfileLevel_H264_Main_AutoLevel)
        case .h265hevc:
            if database.color.space == .hlgBt2020 {
                media.setVideoProfile(profile: kVTProfileLevel_HEVC_Main10_AutoLevel)
            } else {
                media.setVideoProfile(profile: kVTProfileLevel_HEVC_Main_AutoLevel)
            }
        }
        media.setAllowFrameReordering(value: stream.bFrames)
    }

    private func setStreamAdaptiveResolution() {
        media.setStreamAdaptiveResolution(value: stream.adaptiveEncoderResolution)
    }

    private func setStreamKeyFrameInterval() {
        media.setStreamKeyFrameInterval(seconds: stream.maxKeyFrameInterval)
    }

    func isStreamConfigured() -> Bool {
        return stream != fallbackStream
    }

    func isStreamConnected() -> Bool {
        return streamState == .connected
    }

    func isStreaming() -> Bool {
        return streaming
    }

    func updateStreamUptime(now: ContinuousClock.Instant) {
        if let streamStartTime, isStreamConnected() {
            let elapsed = now - streamStartTime
            streamUptime.uptime = uptimeFormatter.string(from: Double(elapsed.components.seconds))!
        } else if streamUptime.uptime != noValue {
            streamUptime.uptime = noValue
        }
    }

    private func makeYouAreLiveToast() {
        makeToast(title: String(localized: "🎉 You are LIVE at \(stream.name) 🎉"))
    }

    func makeStreamEndedToast(subTitle: String? = nil, onTapped: (() -> Void)? = nil) {
        makeToast(
            title: String(localized: "🤟 Stream ended 🤟"), subTitle: subTitle, onTapped: onTapped)
    }

    private func makeConnectFailureToast(subTitle: String) {
        makeErrorToast(
            title: failedToConnectMessage(stream.name),
            subTitle: subTitle,
            vibrate: true)
    }

    private func makeFffffToast(subTitle: String) {
        makeErrorToast(
            title: fffffMessage,
            font: .system(size: 64).bold(),
            subTitle: subTitle,
            vibrate: true
        )
    }

    private func onConnected() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        connectFailureCount = 0
        makeYouAreLiveToast()
        streamStartTime = .now
        streamState = .connected
        updateStreamUptime(now: .now)
    }

    private func onDisconnected(reason: String) {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
        guard streaming else {
            return
        }
        logger.info("stream: Disconnected with reason \(reason)")

        if streamState == .connected {
            // Was live, lost connection mid-stream — always retry, reset counter
            connectFailureCount = 0
            streamTotalBytes += UInt64(media.streamTotal())
            streamingHistoryStream?.numberOfFffffs! += 1
            makeFffffToast(subTitle: String(localized: "Attempting again in 5 seconds."))
        } else if streamState == .connecting {
            // Never connected — count failures
            connectFailureCount += 1
            if connectFailureCount >= maxConnectFailures {
                logger.warning("stream: Giving up after \(connectFailureCount) failed attempts")
                connectFailureCount = 0
                streamState = .disconnected
                // stopStream() shows "Stream ended" toast — show error toast AFTER
                // so it overwrites the generic "ended" message.
                _ = stopStream()
                makeErrorToast(
                    title: failedToConnectMessage(stream.name),
                    subTitle: String(
                        localized: "Could not connect after \(maxConnectFailures) attempts."
                    ),
                    vibrate: true
                )
                return
            }
            makeConnectFailureToast(
                subTitle: String(
                    localized: "Attempt \(connectFailureCount)/\(maxConnectFailures). Retrying in 5 seconds."
                )
            )
        }

        streamState = .disconnected
        stopNetStream()
        reconnectTimer.startSingleShot(timeout: 5) {
            logger.info("stream: Reconnecting (attempt \(self.connectFailureCount + 1))")
            self.startNetStream()
        }
    }

    private func handleSrtConnected() {
        onConnected()
    }

    private func handleSrtDisconnected(reason: String) {
        onDisconnected(reason: reason)
    }

    private func handleRtmpConnected() {
        onConnected()
    }

    private func handleRtmpDisconnected(message: String) {
        onDisconnected(reason: "RTMP disconnected with message \(message)")
    }

    private func handleRtmpDestinationConnected(destination: String) {
        makeToast(title: String(localized: "🎉 You are LIVE at multi stream \(destination) 🎉"))
    }

    private func handleRtmpDestinationDisconnected(destination: String) {
        makeErrorToast(
            title: String(localized: "😢 Multi stream \(destination) failed 😢"),
            subTitle: String(localized: "Attempting again in 5 seconds."))
    }

    private func handleRistConnected() {
        DispatchQueue.main.async {
            self.onConnected()
        }
    }

    private func handleRistDisconnected() {
        DispatchQueue.main.async {
            self.onDisconnected(reason: "RIST disconnected")
        }
    }

    private func handleAudioBuffer(sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async {
            self.speechToText.append(sampleBuffer: sampleBuffer)
        }
    }

    func updateBondingStatistics() {
        if isStreamConnected() {
            if let connections = media.srtlaConnectionStatistics() {
                handleBondingStatistics(connections: connections)
                return
            }
            if let connections = media.ristBondingStatistics() {
                handleBondingStatistics(connections: connections)
                return
            }
        }
        if bonding.statistics != noValue {
            bonding.statistics = noValue
        }
    }

    private func handleBondingStatistics(connections: [BondingConnection]) {
        if let (message, rtts, percentages) = bonding.statisticsFormatter.format(connections) {
            bonding.statistics = message
            bonding.rtts = rtts
            bonding.pieChartPercentages = percentages
        }
    }

    func updateSpeed(now: ContinuousClock.Instant) {
        if isLive {
            let speed = Int64(media.getVideoStreamBitrate(bitrate: stream.bitrate))
            checkLowBitrate(speed: speed, now: now)
            checkVideoFrameStall(now: now)
            streamingHistoryStream?.updateBitrate(bitrate: speed)
            let speedMbpsOneDecimal = String(format: "%.1f", Double(speed) / 1_000_000)
            if speedMbpsOneDecimal != bitrate.speedMbpsOneDecimal {
                bitrate.speedMbpsOneDecimal = speedMbpsOneDecimal
            }
            let speedString = formatBytesPerSecond(speed: speed)
            let total = sizeFormatter.string(fromByteCount: media.streamTotal())
            let numberOfDestinations = media.getNumberOfDestinations()
            let speedAndTotal: String
            if numberOfDestinations == 1 {
                speedAndTotal = String(localized: "\(speedString) (\(total))")
            } else {
                speedAndTotal = String(
                    localized: "\(speedString) x\(numberOfDestinations) (\(total))")
            }
            if speedAndTotal != bitrate.speedAndTotal {
                bitrate.speedAndTotal = speedAndTotal
            }
            let bitrateStatusIconColor: Color?
            if speed < stream.bitrate / 5 {
                bitrateStatusIconColor = .red
            } else if speed < stream.bitrate / 2 {
                bitrateStatusIconColor = .orange
            } else {
                bitrateStatusIconColor = nil
            }
            if bitrateStatusIconColor != bitrate.statusIconColor {
                bitrate.statusIconColor = bitrateStatusIconColor
            }
            if isWatchLocal() {
                sendSpeedAndTotalToWatch(speedAndTotal: bitrate.speedAndTotal)
            }
        } else if bitrate.speedAndTotal != noValue {
            bitrate.speedMbpsOneDecimal = noValue
            bitrate.speedAndTotal = noValue
            if isWatchLocal() {
                sendSpeedAndTotalToWatch(speedAndTotal: bitrate.speedAndTotal)
            }
        }
    }

    private func updateCameraControls() {
        media.setCameraControls(enabled: database.cameraControlsEnabled)
    }

    func setCameraControlsEnabled() {
        cameraControlEnabled = database.cameraControlsEnabled
        media.setCameraControls(enabled: database.cameraControlsEnabled)
    }

    func updateSrtlaPriorities() {
        media.setConnectionPriorities(
            connectionPriorities: stream.srt.connectionPriorities!.clone())
    }

    private func checkLowBitrate(speed: Int64, now: ContinuousClock.Instant) {
        guard database.lowBitrateWarning else {
            return
        }
        guard streamState == .connected else {
            return
        }
        if speed < 500_000, now > latestLowBitrateTime + .seconds(15) {
            makeWarningToast(title: lowBitrateMessage, vibrate: true)
            latestLowBitrateTime = now
        }
    }

    private func checkVideoFrameStall(now: ContinuousClock.Instant) {
        guard streamState == .connected else {
            return
        }
        guard let lastFrameTime = media.getLastVideoFrameTime() else {
            return
        }
        let elapsed = lastFrameTime.duration(to: now)
        if elapsed > .seconds(10), now > latestVideoStallWarningTime + .seconds(30) {
            logger.warning("stream: No video frames for \(elapsed.components.seconds)s while connected")
            makeWarningToast(
                title: String(localized: "⚠️ Video capture interrupted"),
                subTitle: String(localized: "Camera may have been interrupted by another app")
            )
            latestVideoStallWarningTime = now
        }
    }

    private func handleLowFpsImage(image: Data?, frameNumber: UInt64) {
        guard let image else {
            return
        }
        DispatchQueue.main.async { [self] in
            if frameNumber % lowFpsImageFps == 0 {
                if isWatchLocal() {
                    sendPreviewToWatch(image: image)
                }
            }
            if isRemoteControlAssistantRequestingPreview,
                database.remoteControl.streamer.previewFps > 0
            {
                sendPreviewToRemoteControlAssistant(preview: image)
            }
        }
    }

    private func handleFindVideoFormatError(findVideoFormatError: String, activeFormat: String) {
        makeErrorToastMain(title: findVideoFormatError, subTitle: activeFormat)
    }

    private func handleAttachCameraError() {
        makeErrorToastMain(
            title: String(localized: "Camera capture setup error"),
            subTitle: videoCaptureError()
        )
    }

    private func handleCaptureSessionError(message: String) {
        makeErrorToastMain(title: message, subTitle: videoCaptureError())
    }

    private func handleBufferedVideoReady(cameraId: UUID) {
        activeBufferedVideoIds.insert(cameraId)
        var isNetwork = false
        if let stream = getRtmpStream(id: cameraId) {
            isNetwork = true
            stream.connected = true
        } else if let stream = getSrtlaStream(id: cameraId) {
            isNetwork = true
            stream.connected = true
        } else if let stream = getRistStream(id: cameraId) {
            isNetwork = true
            stream.connected = true
        }
        if isNetwork {
            markMicAsConnected(id: "\(cameraId) 0")
            switchMicIfNeededAfterNetworkCameraChange()
        }
        updateDisconnectProtectionVideoSourceConnected()
    }

    private func handleBufferedVideoRemoved(cameraId: UUID) {
        activeBufferedVideoIds.remove(cameraId)
        var isNetwork = false
        if let stream = getRtmpStream(id: cameraId) {
            isNetwork = true
            stream.connected = false
        } else if let stream = getSrtlaStream(id: cameraId) {
            isNetwork = true
            stream.connected = false
        } else if let stream = getRistStream(id: cameraId) {
            isNetwork = true
            stream.connected = false
        }
        if isNetwork {
            markMicAsDisconnected(id: "\(cameraId) 0")
            switchMicIfNeededAfterNetworkCameraChange()
            if isCurrentScenesVideoSourceNetwork(cameraId: cameraId) {
                updateAutoSceneSwitcherVideoSourceDisconnected()
            }
        }
        updateDisconnectProtectionVideoSourceDisconnected()
    }

    private func handleRecorderFinished() {}

    private func handleNoTorch() {
        DispatchQueue.main.async { [self] in
            if !streamOverlay.isFrontCameraSelected {
                makeErrorToast(
                    title: String(localized: "Torch unavailable in this scene."),
                    subTitle: String(localized: "Normally only available for built-in cameras.")
                )
            }
        }
    }

    func toggleStream() {
        if isLive {
            _ = stopStream()
        } else {
            startStream()
        }
    }

    func setIsLive(value: Bool) {
        isLive = value
        if isWatchLocal() {
            sendIsLiveToWatch(isLive: isLive)
        }
        remoteControlStreamer?.stateChanged(state: RemoteControlState(streaming: isLive))
    }

    func setStreamFps(fps: Int? = nil) {
        media.setStreamFps(fps: fps ?? stream.fps, preferAutoFps: stream.autoFps)
    }

    func setStreamBitrate(stream: SettingsStream) {
        media.setVideoStreamBitrate(bitrate: stream.bitrate)
        updateStatusStreamText()
    }

    func getBitratePresetByBitrate(bitrate: UInt32) -> SettingsBitratePreset? {
        return database.bitratePresets.first(where: { preset in
            preset.bitrate == bitrate
        })
    }

    func setBitrate(bitrate: UInt32) {
        if bitrate != stream.bitrate {
            stream.bitrate = bitrate
        }
        if stream.enabled {
            setStreamBitrate(stream: stream)
        }
        guard let preset = getBitratePresetByBitrate(bitrate: bitrate) else {
            return
        }
        remoteControlStreamer?.stateChanged(state: RemoteControlState(bitrate: preset.id))
    }

    private func getBitrate() -> UInt32 {
        return statusTopRight.isLowPowerMode ? lowPowerBitrate : stream.bitrate
    }

    func setAudioStreamBitrate(stream: SettingsStream) {
        media.setAudioStreamBitrate(bitrate: stream.audioBitrate)
        updateStatusStreamText()
    }

    func setAudioStreamFormat(format: AudioEncoderSettings.Format) {
        media.setAudioStreamFormat(format: format)
        updateStatusStreamText()
    }

    func setAudioChannelsMap(channelsMap: [Int: Int]) {
        media.setAudioChannelsMap(channelsMap: channelsMap)
    }

    func isShowingStatusStream() -> Bool {
        return database.show.stream && isStreamConfigured()
    }

    func updateBitrateStatus() {
        defer {
            previousBitrateStatusColorSrtDroppedPacketsTotal = media.srtDroppedPacketsTotal
            previousBitrateStatusNumberOfFailedEncodings = numberOfFailedEncodings
        }
        let newBitrateStatusColor: Color
        if media.srtDroppedPacketsTotal > previousBitrateStatusColorSrtDroppedPacketsTotal {
            newBitrateStatusColor = .red
        } else if numberOfFailedEncodings > previousBitrateStatusNumberOfFailedEncodings {
            newBitrateStatusColor = .red
        } else {
            newBitrateStatusColor = .white
        }
        if newBitrateStatusColor != bitrate.statusColor {
            bitrate.statusColor = newBitrateStatusColor
        }
    }

    func updateAdaptiveBitrate() {
        guard streaming else {
            return
        }
        if let (lines, actions) = media.updateAdaptiveBitrate(
            overlay: database.debug.debugOverlay,
            relaxed: relaxedBitrate
        ) {
            latestDebugLines = lines
            latestDebugActions = actions
        }
    }

    func updateDebugOverlay() {
        if database.debug.debugOverlay {
            var lines = [String(localized: "CPU: \(Int(debugOverlay.cpuUsage))")]
                + latestDebugLines
                + latestDebugActions
            // Append server-side metrics when streaming via zap-stream-core
            if stream.zapStreamCoreEnabled, isLive {
                if let fps = zapStreamServerFps {
                    lines.append("Server FPS: \(Int(fps))")
                }
                if let viewers = zapStreamServerViewers {
                    lines.append("Viewers: \(viewers)")
                }
                if let lastSeg = zapStreamLastSegmentTime {
                    let age = Int(Date().timeIntervalSince(lastSeg))
                    lines.append("Segment age: \(age)s")
                }
            }
            debugOverlay.debugLines = lines
            if logger.debugEnabled, isLive {
                logger.debug(latestDebugLines.joined(separator: ", "))
            }
        } else if !debugOverlay.debugLines.isEmpty {
            debugOverlay.debugLines = []
        }
    }

    func setPixelFormat() {
        for (format, type) in zip(pixelFormats, pixelFormatTypes)
        where
            database.debug.pixelFormat == format
        {
            logger.info("Setting pixel format \(format)")
            pixelFormatType = type
        }
    }

    func startLowPowerMode() {
        guard database.debug.autoLowPowerMode else {
            return
        }
        guard !statusTopRight.isLowPowerMode else {
            return
        }
        statusTopRight.isLowPowerMode = true
        logger.info("Starting low power mode")
        switch stream.fps {
        case 50, 100:
            setStreamFps(fps: 25)
        case 60, 120:
            setStreamFps(fps: 30)
        default:
            break
        }
        switch stream.resolution {
        case .r3840x2160, .r2560x1440, .r1920x1080:
            setStreamResolution(resolution: .r1280x720)
        default:
            break
        }
        if stream.bitrate > lowPowerBitrate {
            media.setVideoStreamBitrate(bitrate: lowPowerBitrate)
        }
    }

    func stopLowPowerMode() {
        guard database.debug.autoLowPowerMode else {
            return
        }
        guard statusTopRight.isLowPowerMode else {
            return
        }
        statusTopRight.isLowPowerMode = false
        logger.info("Stopping low power mode")
        setStreamFps()
        setStreamResolution()
        setBitrate(bitrate: stream.bitrate)
    }
}

extension Model: MediaDelegate {
    func mediaOnSrtConnected() {
        handleSrtConnected()
    }

    func mediaOnSrtDisconnected(_ reason: String) {
        handleSrtDisconnected(reason: reason)
    }

    func mediaOnRtmpConnected() {
        handleRtmpConnected()
    }

    func mediaOnRtmpDisconnected(_ message: String) {
        handleRtmpDisconnected(message: message)
    }

    func mediaOnRtmpDestinationConnected(_ destination: String) {
        handleRtmpDestinationConnected(destination: destination)
    }

    func mediaOnRtmpDestinationDisconnected(_ destination: String) {
        handleRtmpDestinationDisconnected(destination: destination)
    }

    func mediaOnRistConnected() {
        handleRistConnected()
    }

    func mediaOnRistDisconnected() {
        handleRistDisconnected()
    }

    func mediaOnAudioMuteChange() {
        updateAudioLevel()
    }

    func mediaOnAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        handleAudioBuffer(sampleBuffer: sampleBuffer)
    }

    func mediaOnLowFpsImage(_ lowFpsImage: Data?, _ frameNumber: UInt64) {
        handleLowFpsImage(image: lowFpsImage, frameNumber: frameNumber)
    }

    func mediaOnFindVideoFormatError(_ findVideoFormatError: String, _ activeFormat: String) {
        handleFindVideoFormatError(
            findVideoFormatError: findVideoFormatError, activeFormat: activeFormat)
    }

    func mediaOnAttachCameraError() {
        handleAttachCameraError()
    }

    func mediaOnCaptureSessionError(_ message: String) {
        handleCaptureSessionError(message: message)
    }

    func mediaOnBufferedVideoReady(cameraId: UUID) {
        DispatchQueue.main.async {
            self.handleBufferedVideoReady(cameraId: cameraId)
        }
    }

    func mediaOnBufferedVideoRemoved(cameraId: UUID) {
        DispatchQueue.main.async {
            self.handleBufferedVideoRemoved(cameraId: cameraId)
        }
    }

    func mediaOnRecorderInitSegment(data: Data) {
        handleRecorderInitSegment(data: data)
    }

    func mediaOnRecorderDataSegment(segment: RecorderDataSegment) {
        handleRecorderDataSegment(segment: segment)
    }

    func mediaOnRecorderFinished() {
        handleRecorderFinished()
    }

    func mediaOnNoTorch() {
        handleNoTorch()
    }

    func mediaStrlaRelayDestinationAddress(address: String, port: UInt16) {
        moblink.streamer?.startTunnels(address: address, port: port)
    }

    func mediaSetZoomX(x: Float) {
        setZoomX(x: x)
    }

    func mediaSetExposureBias(bias: Float) {
        setExposureBias(bias: bias)
    }

    func mediaSelectedFps(fps: Double, auto: Bool) {
        DispatchQueue.main.async {
            self.selectedFps = Int(fps)
            self.autoFps = auto
            self.updateStatusStreamText()
        }
    }

    func mediaError(error: Error) {
        makeErrorToastMain(
            title: error.localizedDescription, subTitle: tryGetToastSubTitle(error: error))
    }

    // MARK: - Zap Stream Core Methods

    func startZapStreamCoreStream(delayed: Bool = false) {
        logger.info("zap-stream-core: Start")

        guard !streaming else {
            return
        }
        if delayed, !isLive {
            return
        }

        // ── VALIDATION PHASE (no state changes yet) ──

        // Check TOS acceptance
        if !zapStreamCoreTosAccepted {
            makeErrorToast(
                title: String(localized: "Terms of Service Required"),
                subTitle: String(
                    localized: "Accept the terms in your stream settings to go live."
                )
            )
            return
        }

        // Check balance is sufficient (if known)
        if let balance = zapStreamCoreBalance, balance <= 0 {
            makeErrorToast(
                title: String(localized: "Insufficient Balance"),
                subTitle: String(
                    localized: "Top up your zap.stream balance to go live."
                )
            )
            return
        }

        // Check stream URL is configured
        let url = stream.url
        guard url != defaultStreamUrl, !url.isEmpty else {
            makeErrorToast(
                title: String(localized: "Stream Not Configured"),
                subTitle: String(
                    localized: "Open stream settings to connect to zap.stream."
                )
            )
            return
        }

        // Check URL is a valid streaming protocol (not HTTPS fallback)
        guard url.hasPrefix("rtmp://") || url.hasPrefix("rtmps://")
              || url.hasPrefix("srt://") || url.hasPrefix("srtla://") else {
            // URL looks wrong — try to auto-fetch from API
            fetchStreamUrlThenStart(delayed: delayed)
            return
        }

        // ── EXECUTION PHASE (state changes happen here) ──

        // Always (re-)create the API client with current stream settings so that
        // title/description changes made in PreStreamSheet are picked up.
        let config = ZapStreamCoreConfig(
            baseUrl: stream.zapStreamCoreBaseUrl,
            streamTitle: stream.zapStreamCoreStreamTitle.isEmpty
                ? stream.name : stream.zapStreamCoreStreamTitle,
            streamDescription: stream.zapStreamCoreStreamDescription,
            isPublic: stream.zapStreamCoreIsPublic
        )
        zapStreamCoreApiClient = ZapStreamCoreApiClient(config: config)

        // Initialize zap-stream-core stream if not already done
        if zapStreamCoreStream == nil {
            zapStreamCoreStream = ZapStreamCoreStream(
                apiClient: zapStreamCoreApiClient!,
                processor: media.getProcessor()!,
                delegate: self
            )
            zapStreamCoreStream?.setPreferredProtocol(stream.zapStreamCorePreferredProtocol)
        }

        if database.location.resetWhenGoingLive {
            resetLocationData()
        }
        streamLog.removeAll()
        setIsLive(value: true)
        streaming = true
        streamTotalBytes = 0
        streamTotalChatMessages = 0
        updateScreenAutoOff()

        // Push metadata to server BEFORE starting RTMP connection.
        pushZapStreamCoreMetadata()

        // Subscribe to our own live event BEFORE starting the RTMP connection.
        if let userPubkey = appState?.keypair?.publicKey.hex {
            appState?.subscribeToOwnLiveEvent(pubkey: userPubkey)
        }

        startNetStream()

        startFetchingYouTubeChatVideoId()
        if stream.recording.autoStartRecording {
            startRecording()
        }
        if stream.obsAutoStartStream {
            obsStartStream()
        }
        if stream.obsAutoStartRecording {
            obsStartRecording()
        }
        streamingHistoryStream = StreamingHistoryStream(settings: stream.clone())
        streamingHistoryStream!.updateHighestThermalState(
            thermalState: ThermalState(from: statusOther.thermalState))
        streamingHistoryStream!.updateLowestBatteryLevel(level: battery.level)

        // Ensure the nostr chat bridge is running now that we're live.
        // Ensure the nostr chat bridge is running now that we're live.
        ensureNostrChatBridge()

        // Start observing for the live event so we can connect the metrics WebSocket.
        startZapStreamMetricsObserver()
    }

    /// Attempts to fetch the stream URL from the API when the stored URL is invalid.
    /// On success, retries startZapStreamCoreStream with the correct URL.
    private func fetchStreamUrlThenStart(delayed: Bool) {
        guard let appState else {
            makeErrorToast(
                title: String(localized: "Sign In Required"),
                subTitle: String(localized: "Please sign in to stream.")
            )
            return
        }

        logger.info("zap-stream-core: Fetching stream URL from API...")
        let config = ZapStreamCoreConfig(baseUrl: stream.zapStreamCoreBaseUrl)
        let client = ZapStreamCoreApiClient(config: config)

        var cancellable: AnyCancellable?
        cancellable = client.getAccountInfo(appState: appState)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.makeErrorToast(
                            title: String(localized: "Connection Failed"),
                            subTitle: error.localizedDescription
                        )
                    }
                    _ = cancellable
                },
                receiveValue: { [weak self] account in
                    guard let self else { return }
                    self.zapStreamCoreTosAccepted = account.tos?.accepted ?? false
                    self.zapStreamCoreTosLink = account.tos?.link
                    self.zapStreamCoreBalance = account.balance
                    self.zapStreamCoreHasNwc = account.hasNwc
                    if let cost = account.endpoints.first?.cost {
                        self.zapStreamCoreRate = cost.rate
                    }

                    if let endpoint = account.endpoints.first {
                        let fullUrl = "\(endpoint.url)/\(endpoint.key)"
                        self.stream.url = fullUrl
                        self.stream.zapStreamCoreStreamKey = endpoint.key
                        logger.info("zap-stream-core: Fetched URL: \(fullUrl)")
                        self.startZapStreamCoreStream(delayed: delayed)
                    } else {
                        self.makeErrorToast(
                            title: String(localized: "No Stream Endpoint"),
                            subTitle: String(
                                localized: "Top up your balance to get a streaming endpoint."
                            )
                        )
                    }
                }
            )
    }

    func stopZapStreamCoreStream() {
        logger.info("zap-stream-core: Stop")
        zapStreamCoreStream?.stopStreaming()
    }

    /// Push stream metadata to the server (fire-and-forget).
    /// Updates account defaults so the server uses correct metadata when creating the Nostr event.
    private func pushZapStreamCoreMetadata() {
        guard let appState, let apiClient = zapStreamCoreApiClient else { return }

        var cancellable: AnyCancellable?
        cancellable = apiClient.updateStreamEvent(
            appState: appState,
            title: stream.zapStreamCoreStreamTitle.isEmpty
                ? stream.name : stream.zapStreamCoreStreamTitle,
            summary: stream.zapStreamCoreStreamDescription.isEmpty
                ? nil : stream.zapStreamCoreStreamDescription,
            image: stream.zapStreamCoreStreamImage.isEmpty
                ? nil : stream.zapStreamCoreStreamImage,
            tags: stream.zapStreamCoreStreamTags.isEmpty
                ? nil : stream.zapStreamCoreStreamTags,
            contentWarning: stream.zapStreamCoreContentWarning.isEmpty
                ? nil : stream.zapStreamCoreContentWarning,
            goal: stream.zapStreamCoreGoal.isEmpty
                ? nil : stream.zapStreamCoreGoal
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    logger.warning("zap-stream-core: Metadata push failed: \(error)")
                    self?.makeWarningToast(
                        title: String(localized: "Stream info may not be updated"),
                        subTitle: nil
                    )
                }
                cancellable = nil // Release after completion
            },
            receiveValue: { _ in
                logger.info("zap-stream-core: Metadata pushed successfully")
            }
        )
    }

    /// Push metadata updates while live (debounced by caller).
    func updateZapStreamCoreMetadata() {
        guard streaming, stream.zapStreamCoreEnabled else { return }
        pushZapStreamCoreMetadata()
    }

    func setupZapStreamCore() {
        guard stream.zapStreamCoreEnabled else {
            zapStreamCoreApiClient = nil
            zapStreamCoreStream = nil
            return
        }

        let config = ZapStreamCoreConfig(
            baseUrl: stream.zapStreamCoreBaseUrl,
            streamTitle: stream.zapStreamCoreStreamTitle.isEmpty
                ? stream.name : stream.zapStreamCoreStreamTitle,
            streamDescription: stream.zapStreamCoreStreamDescription,
            isPublic: stream.zapStreamCoreIsPublic
        )

        // Use the existing AppState for Nostr authentication
        zapStreamCoreApiClient = ZapStreamCoreApiClient(config: config)

        if let processor = media.getProcessor() {
            zapStreamCoreStream = ZapStreamCoreStream(
                apiClient: zapStreamCoreApiClient!,
                processor: processor,
                delegate: self
            )
            zapStreamCoreStream?.setPreferredProtocol(stream.zapStreamCorePreferredProtocol)
            zapStreamCoreStream?.setAppState(appState!)
        }
    }
}

// MARK: - ZapStreamCoreStreamDelegate

extension Model: ZapStreamCoreStreamDelegate {
    func zapStreamCoreOnError(error: Error) {
        DispatchQueue.main.async {
            self.makeErrorToast(
                title: String(localized: "Zap Stream Error"),
                subTitle: error.localizedDescription
            )
        }
    }
}

// MARK: - Zap Stream Metrics WebSocket

extension Model {
    /// Start observing for the own live event so we can connect the metrics WebSocket
    /// once the stream_id is known. Called from startZapStreamCoreStream().
    func startZapStreamMetricsObserver() {
        guard let appState, let keypair = appState.keypair else { return }

        metricsLiveEventCancellable = appState.$liveActivitiesEvents
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] allEvents in
                guard let self else { return }
                // Already connected — don't reconnect
                guard self.zapStreamMetricsClient == nil else { return }
                guard self.streaming, self.stream.zapStreamCoreEnabled else { return }

                let userPubkey = keypair.publicKey.hex
                let allLive = allEvents.values.flatMap { $0 }
                let ownLive = allLive.filter { $0.hostPubkeyHex == userPubkey && $0.status == .live }
                guard let event = ownLive.max(by: { $0.createdAt < $1.createdAt }),
                      let streamId = event.identifier,
                      !streamId.isEmpty
                else { return }

                logger.info("zap-stream-metrics: Own live event found, stream_id=\(streamId)")
                let client = ZapStreamCoreMetricsClient(
                    baseUrl: self.stream.zapStreamCoreBaseUrl,
                    keypair: keypair
                )
                client.delegate = self
                client.connect(streamId: streamId)
                self.zapStreamMetricsClient = client
            }
    }

    /// Stop the metrics WebSocket and clean up. Called from stopStream().
    func stopZapStreamMetrics() {
        metricsLiveEventCancellable?.cancel()
        metricsLiveEventCancellable = nil
        zapStreamMetricsClient?.disconnect()
        zapStreamMetricsClient = nil
        zapStreamServerViewers = nil
        zapStreamServerFps = nil
        zapStreamLastSegmentTime = nil
        hasShownSegmentStaleWarning = false
        hasShownFpsWarning = false
    }

    /// Check for server-side segment staleness. Call periodically while streaming.
    func checkZapStreamServerHealth() {
        guard stream.zapStreamCoreEnabled, streaming, streamState == .connected else { return }

        // Segment staleness check
        if let lastSegment = zapStreamLastSegmentTime {
            let staleness = Date().timeIntervalSince(lastSegment)
            if staleness > 30, !hasShownSegmentStaleWarning {
                hasShownSegmentStaleWarning = true
                makeWarningToast(
                    title: String(localized: "⚠️ Stream may be interrupted"),
                    subTitle: String(
                        localized: "Server hasn't received video for \(Int(staleness))s."
                    )
                )
            }
            if staleness < 10 {
                hasShownSegmentStaleWarning = false
            }
        }

        // FPS degradation check
        if let serverFps = zapStreamServerFps, serverFps > 0 {
            let targetFps = Double(stream.fps)
            if serverFps < targetFps * 0.5, !hasShownFpsWarning {
                hasShownFpsWarning = true
                makeWarningToast(
                    title: String(localized: "⚠️ Low frame rate on server"),
                    subTitle: String(
                        localized: "Server receiving \(Int(serverFps)) FPS (target: \(Int(targetFps)))."
                    )
                )
            }
            if serverFps >= targetFps * 0.8 {
                hasShownFpsWarning = false
            }
        }
    }
}

// MARK: - ZapStreamCoreMetricsDelegate

extension Model: ZapStreamCoreMetricsDelegate {
    func zapStreamMetricsUpdated(_ metrics: ZapStreamMetrics) {
        DispatchQueue.main.async {
            self.zapStreamServerViewers = metrics.viewers
            self.zapStreamServerFps = metrics.averageFps
            if let date = ISO8601DateFormatter().date(from: metrics.lastSegmentTime) {
                self.zapStreamLastSegmentTime = date
            }
        }
    }

    func zapStreamMetricsError(_ message: String) {
        logger.warning("zap-stream-metrics: \(message)")
    }
}

private func videoCaptureError() -> String {
    return [
        String(localized: "Try to use single or low-energy cameras."),
        String(localized: "Try to lower stream FPS and resolution."),
    ].joined(separator: "\n")
}
