import SwiftUI

struct DjiDeviceScannerSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject private var djiScanner: DjiDeviceScanner = .shared
    @Environment(\.dismiss) var dismiss
    let onChange: (String) -> Void
    @State var selectedId: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !model.bluetoothAllowed {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(bluetoothNotAllowedMessage)
                            .font(.subheadline)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                } else if djiScanner.discoveredDevices.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scanning...")
                                .font(.subheadline.weight(.medium))
                            Text("Looking for nearby DJI devices")
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
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NEARBY DEVICES")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(djiScanner.discoveredDevices, id: \.peripheral.identifier) { device in
                                Button {
                                    onChange(device.peripheral.identifier.uuidString)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.accentPurple.opacity(0.15))
                                                .frame(width: 44, height: 44)
                                            Image(systemName: "appletvremote.gen1")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(.accentPurple)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.peripheral.name ?? String(localized: "Unknown"))
                                                .font(.body.weight(.medium))
                                                .foregroundColor(.primary)
                                            if device.model != .unknown {
                                                Text("\(device.model)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(Color(.tertiaryLabel))
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.secondarySystemGroupedBackground))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Text("Make sure your DJI device is powered on and no other apps are connected via Bluetooth.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Select Device")
        .settingsCloseButton()
        .onAppear { djiScanner.startScanningForDevices() }
        .onDisappear { djiScanner.stopScanningForDevices() }
    }
}
