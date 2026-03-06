import SwiftUI

private struct GoProDeviceSettingsWrapperView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var goProDevices: SettingsGoProDevices
    @ObservedObject var device: SettingsGoProDevice

    var body: some View {
        NavigationLink {
            GoProDeviceSettingsView(goProDevices: goProDevices, device: device)
        } label: {
            HStack {
                DraggableItemPrefixView()
                Text(device.name)
                Spacer()
                Text(formatGoProDeviceState(state: device.state))
                    .foregroundColor(.gray)
            }
        }
    }
}

struct GoProDevicesSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var goProDevices: SettingsGoProDevices

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(goProDevices.devices) { device in
                        GoProDeviceSettingsWrapperView(
                            goProDevices: goProDevices, device: device)
                    }
                    .onMove { froms, to in
                        goProDevices.devices.move(fromOffsets: froms, toOffset: to)
                    }
                    .onDelete { offsets in
                        model.removeGoProDevices(offsets: offsets)
                    }
                }
                CreateButtonView {
                    let device = SettingsGoProDevice()
                    device.name = makeUniqueName(
                        name: SettingsGoProDevice.baseName,
                        existingNames: goProDevices.devices)
                    goProDevices.devices.append(device)
                }
            } footer: {
                SwipeLeftToDeleteHelpView(kind: String(localized: "a device"))
            }
        }
        .navigationTitle("GoPro devices")
    }
}
