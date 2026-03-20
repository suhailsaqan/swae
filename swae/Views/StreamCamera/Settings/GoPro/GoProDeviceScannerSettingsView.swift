import SwiftUI

struct GoProDeviceScannerSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject private var scanner: GoProDeviceScanner = .shared
    @Environment(\.dismiss) var dismiss
    let onChange: (String, String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !model.bluetoothAllowed {
                    bluetoothDeniedCard
                } else if scanner.discoveredDevices.isEmpty {
                    scanningCard
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NEARBY GOPROS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(scanner.discoveredDevices, id: \.peripheral.identifier) { device in
                                Button {
                                    onChange(device.peripheral.identifier.uuidString, device.name)
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
                                        Text(device.name)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(.primary)
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

                Text("Make sure your GoPro is powered on and in pairing mode.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Select GoPro")
        .settingsCloseButton()
        .onAppear { scanner.startScanningForDevices() }
        .onDisappear { scanner.stopScanningForDevices() }
    }

    private var bluetoothDeniedCard: some View {
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
    }

    private var scanningCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
            VStack(alignment: .leading, spacing: 2) {
                Text("Scanning...")
                    .font(.subheadline.weight(.medium))
                Text("Looking for nearby GoPro cameras")
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
}
