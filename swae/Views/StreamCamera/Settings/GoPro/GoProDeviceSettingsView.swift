import NetworkExtension
import SwiftUI

func formatGoProDeviceState(state: GoProDeviceState?) -> String {
    switch state {
    case nil, .idle:
        return String(localized: "Not started")
    case .discovering:
        return String(localized: "Discovering")
    case .connecting:
        return String(localized: "Connecting")
    case .discoveringServices, .subscribing:
        return String(localized: "Pairing")
    case .scanning:
        return String(localized: "Scanning WiFi")
    case .connectingToWifi:
        return String(localized: "Joining WiFi")
    case .wifiSetupFailed:
        return String(localized: "WiFi setup failed")
    case .configuringStream:
        return String(localized: "Configuring stream")
    case .pollingStatus:
        return String(localized: "Preparing to stream")
    case .startingStream:
        return String(localized: "Starting stream")
    case .streaming:
        return String(localized: "Streaming")
    case .stoppingStream:
        return String(localized: "Stopping stream")
    }
}

private func rtmpStreamUrl(address: String, port: UInt16, streamKey: String) -> String {
    return "rtmp://\(address):\(port)\(rtmpServerApp)/\(streamKey)"
}

private struct GoProDeviceSelectView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var device: SettingsGoProDevice

    private func onDeviceChange(id: String, name: String) {
        guard let deviceId = UUID(uuidString: id) else { return }
        device.bluetoothPeripheralId = deviceId
        device.bluetoothPeripheralName = name
    }

    var body: some View {
        Section {
            NavigationLink {
                GoProDeviceScannerSettingsView(onChange: onDeviceChange)
            } label: {
                Text(device.bluetoothPeripheralName ?? String(localized: "Select device"))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .disabled(device.isStarted)
        } header: {
            Text("Device")
        }
    }
}

private struct GoProDeviceWiFiView: View {
    @ObservedObject var device: SettingsGoProDevice

    var body: some View {
        Section {
            if device.bluetoothPeripheralId != nil {
                NavigationLink {
                    GoProWifiPickerView(device: device)
                } label: {
                    HStack {
                        Text("Scan for networks")
                        Spacer()
                        if !device.wifiSsid.isEmpty {
                            Text(device.wifiSsid)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                .disabled(device.isStarted)
            }
            NavigationLink {
                TextEditView(
                    title: String(localized: "SSID"),
                    value: device.wifiSsid,
                    onSubmit: { device.wifiSsid = $0 }
                )
            } label: {
                TextItemView(name: String(localized: "SSID"), value: device.wifiSsid)
            }
            .disabled(device.isStarted)
            NavigationLink {
                TextEditView(
                    title: String(localized: "Password"),
                    value: device.wifiPassword,
                    onSubmit: { device.wifiPassword = $0 }
                )
            } label: {
                TextItemView(
                    name: String(localized: "Password"),
                    value: device.wifiPassword,
                    sensitive: true
                )
            }
            .disabled(device.isStarted)
        } header: {
            Text("WiFi")
        } footer: {
            if !device.wifiSsid.isEmpty && device.wifiPassword.isEmpty {
                Text("⚠️ No password set. Most networks (including Personal Hotspot) require a password.")
            } else {
                Text(
                    """
                    Tap "Scan for networks" to see WiFi networks the GoPro can reach, \
                    or enter credentials manually below.
                    """)
            }
        }
        .onAppear {
            if device.wifiSsid.isEmpty {
                NEHotspotNetwork.fetchCurrent { network in
                    if device.wifiSsid.isEmpty, let network {
                        device.wifiSsid = network.ssid
                    }
                }
                if device.wifiSsid.isEmpty {
                    device.wifiSsid = UIDevice.current.name
                }
            }
        }
    }
}

private struct GoProDeviceRtmpView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var device: SettingsGoProDevice
    @ObservedObject var status: StatusOther
    @ObservedObject var rtmpServer: SettingsRtmpServer

    private func serverUrls() -> [String] {
        guard let stream = model.getRtmpStream(id: device.serverRtmpStreamId) else { return [] }
        var urls: [String] = []
        for status in status.ipStatuses.filter({ $0.ipType == .ipv4 }) {
            urls.append(rtmpStreamUrl(
                address: status.ipType.formatAddress(status.ip),
                port: rtmpServer.port,
                streamKey: stream.streamKey
            ))
        }
        urls.append(rtmpStreamUrl(
            address: personalHotspotLocalAddress,
            port: rtmpServer.port,
            streamKey: stream.streamKey
        ))
        return urls
    }

    var body: some View {
        Section {
            Picker("Type", selection: $device.rtmpUrlType) {
                ForEach(SettingsDjiDeviceUrlType.allCases, id: \.self) {
                    Text($0.toString())
                }
            }
            .disabled(device.isStarted)
            if device.rtmpUrlType == .server {
                if rtmpServer.streams.isEmpty {
                    Text("No RTMP server streams exist")
                } else {
                    Picker("Stream", selection: $device.serverRtmpStreamId) {
                        ForEach(rtmpServer.streams) { stream in
                            Text(stream.name).tag(stream.id)
                        }
                    }
                    .onChange(of: device.serverRtmpStreamId) { _ in
                        device.serverRtmpUrl = serverUrls().first ?? ""
                    }
                    .disabled(device.isStarted)
                    Picker("URL", selection: $device.serverRtmpUrl) {
                        ForEach(serverUrls(), id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .disabled(device.isStarted)
                    if !rtmpServer.enabled {
                        Text("⚠️ The RTMP server is not enabled")
                    }
                }
            } else if device.rtmpUrlType == .custom {
                TextEditNavigationView(
                    title: String(localized: "URL"),
                    value: device.customRtmpUrl,
                    onSubmit: { device.customRtmpUrl = $0 }
                )
                .disabled(device.isStarted)
            }
        } header: {
            Text("RTMP")
        } footer: {
            Text(
                """
                Select Server to stream to Swae's built-in RTMP server. \
                Select Custom to stream to any RTMP destination.
                """)
        }
        .onAppear {
            let streams = rtmpServer.streams
            if !streams.isEmpty {
                if !streams.contains(where: { $0.id == device.serverRtmpStreamId }) {
                    device.serverRtmpStreamId = streams.first!.id
                }
                if !serverUrls().contains(where: { $0 == device.serverRtmpUrl }) {
                    device.serverRtmpUrl = serverUrls().first ?? ""
                }
            }
        }
        Section {
            NavigationLink {
                RtmpServerSettingsView(rtmpServer: rtmpServer)
            } label: {
                Text("RTMP server")
            }
        } header: {
            Text("Shortcut")
        }
    }
}

private struct GoProDeviceQualityView: View {
    @ObservedObject var device: SettingsGoProDevice

    var body: some View {
        Section {
            Picker("Resolution", selection: $device.resolution) {
                ForEach(SettingsGoProDeviceResolution.allCases, id: \.self) {
                    Text($0.rawValue)
                }
            }
            .disabled(device.isStarted)
            Picker("Bitrate", selection: $device.bitrate) {
                ForEach(goProDeviceBitrates, id: \.self) {
                    Text(formatBytesPerSecond(speed: Int64($0)))
                }
            }
            .disabled(device.isStarted)
        } header: {
            Text("Quality")
        }
    }
}

struct GoProDeviceSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var goProDevices: SettingsGoProDevices
    @ObservedObject var device: SettingsGoProDevice

    var body: some View {
        Form {
            Section {
                NameEditView(name: $device.name, existingNames: goProDevices.devices)
            }
            GoProDeviceSelectView(device: device)
            GoProDeviceWiFiView(device: device)
            GoProDeviceRtmpView(
                device: device,
                status: model.statusOther,
                rtmpServer: model.database.rtmpServer
            )
            GoProDeviceQualityView(device: device)
            if device.rtmpUrlType == .server {
                Section {
                    Toggle(isOn: $device.autoRestartStream) {
                        Text("Auto-restart live stream when broken")
                    }
                }
            }
            Section {
                HCenter {
                    Text(formatGoProDeviceState(state: model.getGoProDeviceState(device: device)))
                }
            }
            if !device.isStarted {
                Section {
                    Button {
                        model.startGoProLiveStream(device: device)
                    } label: {
                        HCenter {
                            Text("Start live stream")
                        }
                    }
                    .disabled(!device.canStartLive())
                }
            } else {
                Section {
                    HCenter {
                        Button {
                            model.stopGoProLiveStream(device: device)
                        } label: {
                            Text("Stop live stream")
                        }
                    }
                }
                .foregroundColor(.white)
                .listRowBackground(Color.blue)
            }
        }
        .navigationTitle("GoPro device")
    }
}
