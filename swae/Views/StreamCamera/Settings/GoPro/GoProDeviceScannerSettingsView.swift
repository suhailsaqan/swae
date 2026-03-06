import SwiftUI

struct GoProDeviceScannerSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject private var scanner: GoProDeviceScanner = .shared
    @Environment(\.dismiss) var dismiss
    let onChange: (String, String) -> Void

    var body: some View {
        Form {
            Section {
                if !model.bluetoothAllowed {
                    Text(bluetoothNotAllowedMessage)
                } else if scanner.discoveredDevices.isEmpty {
                    HCenter {
                        ProgressView()
                    }
                } else {
                    List {
                        ForEach(scanner.discoveredDevices, id: \.peripheral.identifier) { device in
                            Button {
                                onChange(device.peripheral.identifier.uuidString, device.name)
                                dismiss()
                            } label: {
                                Text(device.name)
                            }
                        }
                    }
                }
            } footer: {
                Text(
                    """
                    Make sure your GoPro is powered on and in pairing mode \
                    (Preferences → Wireless Connections → Connect Device). \
                    If you don't see your GoPro, turn it off and on again.
                    """)
            }
        }
        .onAppear {
            scanner.startScanningForDevices()
        }
        .onDisappear {
            scanner.stopScanningForDevices()
        }
        .navigationTitle("Select GoPro")
    }
}
