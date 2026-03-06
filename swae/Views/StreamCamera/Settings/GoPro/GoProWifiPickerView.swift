import SwiftUI

struct GoProWifiPickerView: View {
    @ObservedObject var device: SettingsGoProDevice
    @StateObject private var scanner = GoProWifiScanner()
    @Environment(\.dismiss) var dismiss
    @State private var showPasswordPrompt = false
    @State private var selectedEntry: GoProScanEntry?
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                if let error = scanner.error {
                    Text(error)
                        .foregroundColor(.red)
                    Button("Retry") {
                        startScan()
                    }
                } else if scanner.isScanning {
                    HCenter {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Scanning for WiFi networks...")
                                .foregroundColor(.gray)
                        }
                    }
                } else if scanner.scanEntries.isEmpty {
                    Text("No networks found")
                        .foregroundColor(.gray)
                } else {
                    ForEach(scanner.scanEntries, id: \.ssid) { entry in
                        Button {
                            selectNetwork(entry)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.ssid)
                                        .foregroundColor(.primary)
                                    HStack(spacing: 8) {
                                        if entry.isAssociated {
                                            Text("Connected")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                        if entry.isConfigured {
                                            Text("Saved")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                Spacer()
                                signalIcon(bars: entry.signalStrengthBars)
                                if entry.requiresAuth && !entry.isConfigured {
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                if entry.ssid == device.wifiSsid {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Available networks")
            } footer: {
                Text("Networks the GoPro can see. Tap to select.")
            }
        }
        .onAppear {
            startScan()
        }
        .onDisappear {
            scanner.stop()
        }
        .navigationTitle("WiFi Networks")
        .alert("Enter Password", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $password)
            Button("Connect") {
                if let entry = selectedEntry {
                    device.wifiSsid = entry.ssid
                    device.wifiPassword = password
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {
                password = ""
                selectedEntry = nil
            }
        } message: {
            if let entry = selectedEntry {
                Text("Enter the password for \"\(entry.ssid)\"")
            }
        }
    }

    private func startScan() {
        guard let peripheralId = device.bluetoothPeripheralId else {
            scanner.error = "No GoPro device selected"
            return
        }
        scanner.startScan(deviceId: peripheralId)
    }

    private func selectNetwork(_ entry: GoProScanEntry) {
        if entry.isConfigured || entry.isAssociated {
            // No password needed — already saved on the GoPro
            device.wifiSsid = entry.ssid
            dismiss()
        } else if entry.requiresAuth {
            // Need password
            selectedEntry = entry
            password = ""
            showPasswordPrompt = true
        } else {
            // Open network
            device.wifiSsid = entry.ssid
            device.wifiPassword = ""
            dismiss()
        }
    }

    @ViewBuilder
    private func signalIcon(bars: Int) -> some View {
        Image(systemName: "wifi", variableValue: Double(bars) / 3.0)
            .foregroundColor(.gray)
    }
}
