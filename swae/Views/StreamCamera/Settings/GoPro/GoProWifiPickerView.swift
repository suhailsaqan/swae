import SwiftUI

struct GoProWifiPickerView: View {
    @ObservedObject var device: SettingsGoProDevice
    @StateObject private var scanner = GoProWifiScanner()
    @Environment(\.dismiss) var dismiss
    @State private var showPasswordPrompt = false
    @State private var selectedEntry: GoProScanEntry?
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status
                if let error = scanner.error {
                    errorCard(error: error)
                } else if scanner.isScanning {
                    scanningCard
                } else if scanner.scanEntries.isEmpty {
                    emptyCard
                }

                // Network list
                if !scanner.scanEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AVAILABLE NETWORKS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(scanner.scanEntries, id: \.ssid) { entry in
                                networkCard(entry: entry)
                            }
                        }
                    }
                }

                Text("Networks the GoPro can see. Tap to select.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("WiFi Networks")
        .settingsCloseButton()
        .onAppear { startScan() }
        .onDisappear { scanner.stop() }
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
            device.wifiSsid = entry.ssid
            dismiss()
        } else if entry.requiresAuth {
            selectedEntry = entry
            password = ""
            showPasswordPrompt = true
        } else {
            device.wifiSsid = entry.ssid
            device.wifiPassword = ""
            dismiss()
        }
    }

    // MARK: - Cards

    private func errorCard(error: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .font(.subheadline)
                Spacer()
            }
            Button {
                startScan()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.accentPurple)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    private var scanningCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
            VStack(alignment: .leading, spacing: 2) {
                Text("Scanning...")
                    .font(.subheadline.weight(.medium))
                Text("Looking for WiFi networks via GoPro")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var emptyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.secondary)
            Text("No networks found")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func networkCard(entry: GoProScanEntry) -> some View {
        Button {
            selectNetwork(entry)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wifi", variableValue: Double(entry.signalStrengthBars) / 3.0)
                    .font(.body)
                    .foregroundColor(.accentPurple)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.ssid)
                        .font(.body.weight(.medium))
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

                if entry.requiresAuth && !entry.isConfigured {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if entry.ssid == device.wifiSsid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
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
                        entry.ssid == device.wifiSsid ? Color.green.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
