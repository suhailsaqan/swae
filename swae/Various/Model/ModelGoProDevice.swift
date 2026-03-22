import Foundation

class GoProDeviceWrapper {
    let device: GoProDevice
    var autoRestartStreamTimer: DispatchSourceTimer?

    init(device: GoProDevice) {
        self.device = device
    }
}

extension Model {
    /// Call when a GoPro device is created or its settings view appears.
    /// Ensures RTMP server has a stream so canStartLive() works once BLE + WiFi are set.
    func prepareRtmpServerForGoProDevice(_ device: SettingsGoProDevice) {
        guard device.rtmpUrlType == .server else { return }
        ensureRtmpServerReady(for: device)
    }

    func startGoProLiveStream(device: SettingsGoProDevice) {
        // Auto-configure RTMP server if needed for server type
        if device.rtmpUrlType == .server {
            ensureRtmpServerReady(for: device)
        }
        if !goProDeviceWrappers.keys.contains(device.id) {
            let goProDevice = GoProDevice()
            goProDevice.delegate = self
            goProDeviceWrappers[device.id] = GoProDeviceWrapper(device: goProDevice)
        }
        guard let wrapper = goProDeviceWrappers[device.id] else { return }
        device.isStarted = true
        startGoProLiveStreamInternal(wrapper: wrapper, device: device)
    }

    private func ensureRtmpServerReady(for device: SettingsGoProDevice) {
        var needsReload = false
        // Auto-enable RTMP server
        if !database.rtmpServer.enabled {
            database.rtmpServer.enabled = true
            needsReload = true
        }
        // Auto-create a stream if none exist
        if database.rtmpServer.streams.isEmpty {
            let stream = SettingsRtmpServerStream()
            stream.name = device.name
            database.rtmpServer.streams.append(stream)
            device.serverRtmpStreamId = stream.id
            // Build the RTMP URL for the hotspot address
            device.serverRtmpUrl = "rtmp://\(personalHotspotLocalAddress):\(database.rtmpServer.port)\(rtmpServerApp)/\(stream.streamKey)"
            needsReload = true
        }
        // Ensure the selected stream has a non-empty key
        if let stream = getRtmpStream(id: device.serverRtmpStreamId), stream.streamKey.isEmpty {
            stream.streamKey = String(UUID().uuidString.prefix(8)).lowercased()
            needsReload = true
        }
        if needsReload {
            reloadRtmpServer()
        }
    }

    private func startGoProLiveStreamInternal(
        wrapper: GoProDeviceWrapper,
        device: SettingsGoProDevice
    ) {
        let rtmpUrl: String?
        switch device.rtmpUrlType {
        case .server:
            rtmpUrl = device.serverRtmpUrl
        case .custom:
            rtmpUrl = device.customRtmpUrl
        }
        guard let rtmpUrl, let deviceId = device.bluetoothPeripheralId else { return }

        let resolution: GoProWindowSize
        switch device.resolution {
        case .r1080p: resolution = .r1080p
        case .r720p: resolution = .r720p
        case .r480p: resolution = .r480p
        }

        let bitrateKbps = Int32(device.bitrate / 1000)
        wrapper.device.startLiveStream(
            wifiSsid: device.wifiSsid,
            wifiPassword: device.wifiPassword,
            rtmpUrl: rtmpUrl,
            resolution: resolution,
            minimumBitrate: max(bitrateKbps / 2, 1000),
            maximumBitrate: bitrateKbps,
            startingBitrate: bitrateKbps,
            deviceId: deviceId
        )
        startGoProDeviceTimer(wrapper: wrapper, device: device)
    }

    private func startGoProDeviceTimer(wrapper: GoProDeviceWrapper, device: SettingsGoProDevice) {
        wrapper.autoRestartStreamTimer = DispatchSource.makeTimerSource(queue: .main)
        wrapper.autoRestartStreamTimer!.schedule(deadline: .now() + 60)
        wrapper.autoRestartStreamTimer!.setEventHandler { [weak self] in
            self?.makeErrorToast(
                title: String(localized: "Failed to start live stream from GoPro \(device.name)")
            )
            self?.restartGoProLiveStreamIfNeeded(device: device)
        }
        wrapper.autoRestartStreamTimer!.activate()
    }

    private func stopGoProDeviceTimer(wrapper: GoProDeviceWrapper) {
        wrapper.autoRestartStreamTimer?.cancel()
        wrapper.autoRestartStreamTimer = nil
    }

    func stopGoProLiveStream(device: SettingsGoProDevice) {
        device.isStarted = false
        guard let wrapper = goProDeviceWrappers[device.id] else { return }
        wrapper.device.stopLiveStream()
        stopGoProDeviceTimer(wrapper: wrapper)
    }

    func restartGoProLiveStreamIfNeededAfterDelay(device: SettingsGoProDevice) {
        guard let wrapper = goProDeviceWrappers[device.id] else { return }
        wrapper.autoRestartStreamTimer = DispatchSource.makeTimerSource(queue: .main)
        wrapper.autoRestartStreamTimer!.schedule(deadline: .now() + 5)
        wrapper.autoRestartStreamTimer!.setEventHandler { [weak self] in
            self?.restartGoProLiveStreamIfNeeded(device: device)
        }
        wrapper.autoRestartStreamTimer!.activate()
    }

    private func restartGoProLiveStreamIfNeeded(device: SettingsGoProDevice) {
        switch device.rtmpUrlType {
        case .server:
            guard device.autoRestartStream else {
                stopGoProLiveStream(device: device)
                return
            }
        case .custom:
            return
        }
        guard let wrapper = goProDeviceWrappers[device.id], device.isStarted else { return }
        startGoProLiveStreamInternal(wrapper: wrapper, device: device)
    }

    func markGoProIsStreamingIfNeeded(rtmpServerStreamId: UUID) {
        for device in database.goProDevices.devices {
            guard device.rtmpUrlType == .server, device.serverRtmpStreamId == rtmpServerStreamId else {
                continue
            }
            guard let wrapper = goProDeviceWrappers[device.id] else { continue }
            wrapper.autoRestartStreamTimer?.cancel()
            wrapper.autoRestartStreamTimer = nil
        }
    }

    private func getGoProDeviceSettings(goProDevice: GoProDevice) -> SettingsGoProDevice? {
        return database.goProDevices.devices.first(where: { goProDeviceWrappers[$0.id]?.device === goProDevice })
    }

    func getGoProDeviceState(device: SettingsGoProDevice) -> GoProDeviceState? {
        return goProDeviceWrappers[device.id]?.device.getState()
    }

    func reloadGoProDevices() {
        for deviceId in goProDeviceWrappers.keys {
            guard let device = database.goProDevices.devices.first(where: { $0.id == deviceId }) else {
                continue
            }
            guard device.isStarted else { continue }
            guard let wrapper = goProDeviceWrappers[device.id] else { return }
            guard wrapper.device.getState() != .streaming else { return }
            startGoProLiveStream(device: device)
        }
    }

    func autoStartGoProDevices() {
        for device in database.goProDevices.devices where device.isStarted {
            startGoProLiveStream(device: device)
        }
    }

    func removeGoProDevices(offsets: IndexSet) {
        for offset in offsets {
            let device = database.goProDevices.devices[offset]
            stopGoProLiveStream(device: device)
            goProDeviceWrappers.removeValue(forKey: device.id)
        }
        database.goProDevices.devices.remove(atOffsets: offsets)
    }
}

// MARK: - GoProDeviceDelegate

extension Model: GoProDeviceDelegate {
    func goProDeviceStreamingState(_ device: GoProDevice, state: GoProDeviceState) {
        guard let device = getGoProDeviceSettings(goProDevice: device) else { return }
        guard let wrapper = goProDeviceWrappers[device.id] else { return }
        device.state = state
        switch state {
        case .connecting:
            startGoProDeviceTimer(wrapper: wrapper, device: device)
            makeToast(title: String(localized: "Connecting to GoPro \(device.name)"))
        case .connectingToWifi:
            makeToast(title: String(localized: "GoPro \(device.name) joining WiFi"))
        case .streaming:
            if device.rtmpUrlType == .custom {
                stopGoProDeviceTimer(wrapper: wrapper)
                makeToast(title: String(localized: "GoPro \(device.name) streaming to custom URL"))
            }
        case .wifiSetupFailed:
            makeErrorToast(
                title: String(localized: "WiFi setup failed for GoPro \(device.name)"),
                subTitle: String(localized: "Check WiFi SSID and password. Keep Personal Hotspot active.")
            )
        default:
            break
        }
    }
}
