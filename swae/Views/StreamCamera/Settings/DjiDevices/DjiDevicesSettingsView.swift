import NetworkExtension
import SwiftUI

// MARK: - State Formatting

func formatDjiDeviceState(state: DjiDeviceState?) -> String {
    switch state {
    case nil, .idle: return String(localized: "Not started")
    case .discovering: return String(localized: "Discovering")
    case .connecting: return String(localized: "Connecting")
    case .checkingIfPaired, .pairing: return String(localized: "Pairing")
    case .stoppingStream, .cleaningUp: return String(localized: "Stopping stream")
    case .preparingStream: return String(localized: "Preparing to stream")
    case .settingUpWifi: return String(localized: "Setting up WiFi")
    case .wifiSetupFailed: return String(localized: "WiFi setup failed")
    case .configuring: return String(localized: "Configuring")
    case .startingStream: return String(localized: "Starting stream")
    case .streaming: return String(localized: "Streaming")
    default: return String(localized: "Unknown")
    }
}

private func djiStateColor(for state: DjiDeviceState?) -> Color {
    switch state {
    case .streaming: return .green
    case .connecting, .checkingIfPaired, .pairing, .preparingStream,
         .settingUpWifi, .configuring, .startingStream, .stoppingStream,
         .cleaningUp, .discovering:
        return .orange
    case .wifiSetupFailed: return .red
    default: return .secondary
    }
}

// MARK: - DjiDevicesSettingsView

struct DjiDevicesSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var djiDevices: SettingsDjiDevices
    @ObservedObject private var scanner: DjiDeviceScanner = .shared
    @State private var selectedDeviceIndex: Int = 0

    private var devices: [SettingsDjiDevice] {
        djiDevices.devices
    }

    private var selectedDevice: SettingsDjiDevice? {
        guard !devices.isEmpty, selectedDeviceIndex < devices.count else { return nil }
        return devices[selectedDeviceIndex]
    }

    private func ensureAtLeastOneDevice() {
        if devices.isEmpty {
            let device = SettingsDjiDevice()
            device.name = makeUniqueName(name: SettingsDjiDevice.baseName, existingNames: djiDevices.devices)
            djiDevices.devices.append(device)
            model.prepareRtmpServerForDjiDevice(device)
        }
        if selectedDeviceIndex >= devices.count {
            selectedDeviceIndex = 0
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroImageCard

                if devices.count > 1 {
                    deviceSelectorSection
                }

                if let device = selectedDevice {
                    DjiDeviceDetailView(device: device)
                }

                addAnotherButton
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("DJI devices")
        .settingsCloseButton()
        .onAppear {
            ensureAtLeastOneDevice()
            if let device = selectedDevice {
                model.prepareRtmpServerForDjiDevice(device)
                model.setCurrentDjiDevice(device: device)
                autoFillWifi(device: device)
            }
            scanner.startScanningForDevices()
        }
        .onDisappear {
            scanner.stopScanningForDevices()
        }
    }

    private func autoFillWifi(device: SettingsDjiDevice) {
        if device.wifiSsid.isEmpty {
            NEHotspotNetwork.fetchCurrent { network in
                if device.wifiSsid.isEmpty, let network {
                    device.wifiSsid = network.ssid
                }
            }
        }
    }

    // MARK: - Hero Image

    private var heroImageCard: some View {
        VStack(spacing: 0) {
            Image("DjiOa4")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Device Selector

    private var deviceSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR DEVICES")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                Button {
                    selectedDeviceIndex = index
                    model.prepareRtmpServerForDjiDevice(device)
                    model.setCurrentDjiDevice(device: device)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(djiStateColor(for: device.state).opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "video.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(djiStateColor(for: device.state))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            Text(formatDjiDeviceState(state: device.state))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if device.state == .streaming {
                            Text("Streaming")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                index == selectedDeviceIndex ? Color.accentPurple.opacity(0.5) : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        deleteDevice(at: index)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(device.isStarted)
                }
            }

            if devices.count > 1 {
                Text("Long press to delete a device")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func deleteDevice(at index: Int) {
        guard index < devices.count else { return }
        let device = devices[index]
        guard !device.isStarted else { return }
        model.stopDjiDeviceLiveStream(device: device)
        djiDevices.devices.remove(at: index)
        if selectedDeviceIndex >= devices.count {
            selectedDeviceIndex = max(0, devices.count - 1)
        }
        ensureAtLeastOneDevice()
    }

    // MARK: - Add Another

    private var addAnotherButton: some View {
        Button {
            let device = SettingsDjiDevice()
            device.name = makeUniqueName(name: SettingsDjiDevice.baseName, existingNames: djiDevices.devices)
            djiDevices.devices.append(device)
            model.prepareRtmpServerForDjiDevice(device)
            selectedDeviceIndex = devices.count - 1
            autoFillWifi(device: device)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add another DJI device")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Text("Connect via Bluetooth")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundColor(Color(.separator))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DjiDeviceDetailView

/// Child view that observes a single SettingsDjiDevice via @ObservedObject,
/// ensuring SwiftUI re-renders when any @Published property on the device changes.
struct DjiDeviceDetailView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var device: SettingsDjiDevice
    @ObservedObject private var scanner: DjiDeviceScanner = .shared
    @State private var showUrlPicker = false
    @State private var showWifiHelp = false

    var body: some View {
        Group {
            bleSection
            wifiSection
            wifiHelpCard
            qualitySection
            rtmpInfoCard
            advancedLink
            statusCard
            actionButton
        }
    }

    // MARK: - BLE Scanner (inline)

    private var bleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SELECT DEVICE")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                if let name = device.bluetoothPeripheralName {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.body.weight(.medium))
                            Text(device.model != .unknown ? "\(device.model)" : "Paired via Bluetooth")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Change") {
                            device.bluetoothPeripheralId = nil
                            device.bluetoothPeripheralName = nil
                            device.model = .unknown
                            scanner.startScanningForDevices()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.accentPurple)
                        .disabled(device.isStarted)
                    }
                } else {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.accentPurple.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.accentPurple)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Select DJI Device")
                                .font(.body.weight(.medium))
                            if !model.bluetoothAllowed {
                                Text(bluetoothNotAllowedMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Text("Scanning for nearby DJI devices...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if model.bluetoothAllowed && scanner.discoveredDevices.isEmpty {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }

                    if model.bluetoothAllowed {
                        ForEach(scanner.discoveredDevices, id: \.peripheral.identifier) { discovered in
                            Button {
                                device.bluetoothPeripheralName = discovered.peripheral.name
                                device.bluetoothPeripheralId = discovered.peripheral.identifier
                                device.model = discovered.model
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "appletvremote.gen1")
                                        .font(.body)
                                        .foregroundColor(.accentPurple)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(discovered.peripheral.name ?? String(localized: "Unknown"))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.primary)
                                        if discovered.model != .unknown {
                                            Text("\(discovered.model)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(Color(.tertiaryLabel))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                            if discovered.peripheral.identifier != scanner.discoveredDevices.last?.peripheral.identifier {
                                Divider()
                            }
                        }
                    }
                }

                if device.bluetoothPeripheralName == nil {
                    Text("Power on your DJI device. Make sure no other apps are connected to it via Bluetooth.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - WiFi Section

    private var wifiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WIFI NETWORK")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentPurple.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "wifi")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.accentPurple)
                    }
                    Text("WiFi Network")
                        .font(.body.weight(.medium))
                    Spacer()
                }

                VStack(spacing: 10) {
                    HStack {
                        Text("SSID")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .leading)
                        TextField("Network name", text: $device.wifiSsid)
                            .font(.body)
                            .disabled(device.isStarted)
                    }
                    Divider()
                    HStack {
                        Text("Password")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .leading)
                        SecureField("Password", text: $device.wifiPassword)
                            .font(.body)
                            .disabled(device.isStarted)
                    }
                }

                Text("The DJI device will connect to and stream over this WiFi network.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - WiFi Help

    private var wifiHelpCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showWifiHelp.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text("Using your iPhone's hotspot")
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: showWifiHelp ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)

            if showWifiHelp {
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                        .padding(.vertical, 8)

                    Text("Your iPhone can share its internet with the DJI device using Personal Hotspot. Enter your hotspot name as the SSID and your hotspot password above.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("If your hotspot doesn't appear:")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)

                    wifiHelpStep(number: 1, text: "Open iPhone Settings → Personal Hotspot and turn it off")
                    wifiHelpStep(number: 2, text: "Power off your DJI device")
                    wifiHelpStep(number: 3, text: "Turn Personal Hotspot back on and wait about 10 seconds")
                    wifiHelpStep(number: 4, text: "Power on your DJI device")
                    wifiHelpStep(number: 5, text: "Return to Swae and connect your device")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundColor(Color(.separator))
        )
    }

    private func wifiHelpStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentPurple.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.accentPurple)
            }
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUALITY")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                HStack {
                    Text("Resolution")
                    Spacer()
                    Picker("", selection: $device.resolution) {
                        ForEach(SettingsDjiDeviceResolution.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .labelsHidden()
                    .disabled(device.isStarted)
                }
                .padding(.vertical, 4)
                Divider()
                HStack {
                    Text("Bitrate")
                    Spacer()
                    Picker("", selection: $device.bitrate) {
                        ForEach(djiDeviceBitrates, id: \.self) {
                            Text(formatBytesPerSecond(speed: Int64($0))).tag($0)
                        }
                    }
                    .labelsHidden()
                    .disabled(device.isStarted)
                }
                .padding(.vertical, 4)
                if device.model == .osmoAction4 || device.model == .osmoAction5Pro {
                    Divider()
                    HStack {
                        Text("Stabilization")
                        Spacer()
                        Picker("", selection: $device.imageStabilization) {
                            ForEach(SettingsDjiDeviceImageStabilization.allCases, id: \.self) {
                                Text($0.toString()).tag($0)
                            }
                        }
                        .labelsHidden()
                        .disabled(device.isStarted)
                    }
                    .padding(.vertical, 4)
                }
                if device.model == .osmoPocket3 {
                    Divider()
                    HStack {
                        Text("FPS")
                        Spacer()
                        Picker("", selection: $device.fps) {
                            ForEach(djiDeviceFpss, id: \.self) {
                                Text(String($0)).tag($0)
                            }
                        }
                        .labelsHidden()
                        .disabled(device.isStarted)
                    }
                    .padding(.vertical, 4)
                }
                if device.rtmpUrlType == .server {
                    Divider()
                    HStack {
                        Text("Auto-restart")
                        Spacer()
                        Toggle("", isOn: $device.autoRestartStream)
                            .tint(.accentPurple)
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            Text("High bitrates may be unstable.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - RTMP Info Card

    private func rtmpUrls() -> [String] {
        guard let stream = model.getRtmpStream(id: device.serverRtmpStreamId) else { return [] }
        let port = model.database.rtmpServer.port
        let key = stream.streamKey
        var urls: [String] = []
        urls.append("rtmp://\(personalHotspotLocalAddress):\(port)\(rtmpServerApp)/\(key)")
        for status in model.statusOther.ipStatuses.filter({ $0.ipType == .ipv4 }) {
            let addr = status.ipType.formatAddress(status.ip)
            let url = "rtmp://\(addr):\(port)\(rtmpServerApp)/\(key)"
            if !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
    }

    private var rtmpInfoCard: some View {
        VStack(spacing: 8) {
            if !device.serverRtmpUrl.isEmpty || device.rtmpUrlType == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Streaming destination ready")
                                .font(.subheadline.weight(.medium))
                            Text("Your DJI device streams to Swae's built-in server over WiFi.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    if device.rtmpUrlType == .server && !device.serverRtmpUrl.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showUrlPicker.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.caption)
                                Text(device.serverRtmpUrl)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Image(systemName: showUrlPicker ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                        .disabled(device.isStarted)
                    }

                    if showUrlPicker && device.rtmpUrlType == .server {
                        let urls = rtmpUrls()
                        if !urls.isEmpty {
                            VStack(spacing: 4) {
                                ForEach(urls, id: \.self) { url in
                                    Button {
                                        device.serverRtmpUrl = url
                                        showUrlPicker = false
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: url.contains(personalHotspotLocalAddress)
                                                  ? "personalhotspot"
                                                  : "wifi")
                                                .font(.caption)
                                                .frame(width: 20)
                                            Text(url)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            if url == device.serverRtmpUrl {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .foregroundColor(.primary)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Streaming destination not ready")
                            .font(.subheadline.weight(.medium))
                        Text("Tap Advanced to configure manually.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Advanced Link

    private var advancedLink: some View {
        NavigationLink {
            RtmpServerSettingsView(rtmpServer: model.database.rtmpServer)
        } label: {
            HStack {
                Text("Advanced RTMP settings")
                    .font(.footnote)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(Color(.separator).opacity(0.5))
            )
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        let state = device.state
        let color = djiStateColor(for: state)
        let isStreaming = state == .streaming

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatDjiDeviceState(state: state))
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            if isStreaming {
                Text("Live")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .cornerRadius(4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isStreaming ? Color.green.opacity(0.1) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isStreaming ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Action Button

    private var actionButton: some View {
        VStack(spacing: 8) {
            if device.isStarted {
                Button {
                    model.stopDjiDeviceLiveStream(device: device)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("Stop Live Stream")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.red)
                    )
                    .foregroundColor(.white)
                }
            } else {
                Button {
                    model.startDjiDeviceLiveStream(device: device)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Start Live Stream")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(device.canStartLive() ? Color.accentPurple : Color.gray.opacity(0.3))
                    )
                    .foregroundColor(.white)
                }
                .disabled(!device.canStartLive())

                if !device.canStartLive() {
                    Text("Select a device and enter WiFi to start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
