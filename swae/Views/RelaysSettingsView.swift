//
//  RelaysSettingsView.swift
//  swae
//
//  Created by Suhail Saqan on 2/22/25.
//


import Combine
import NostrSDK
import SwiftData
import SwiftUI

struct RelaysSettingsView: View, RelayURLValidating {
    @EnvironmentObject var appState: AppState

    @State private var validatedRelayURL: URL?
    @State private var newRelay: String = ""

    var body: some View {
        List {
            Section(
                content: {
                    if let relayPoolSettings = appState.relayPoolSettings {
                        ForEach(relayPoolSettings.relaySettingsList, id: \.self) { relaySettings in
                            HStack {
                                let relayMarkerBinding = Binding<RelayOption>(
                                    get: {
                                        switch (relaySettings.read, relaySettings.write) {
                                        case (true, true):
                                                .readAndWrite
                                        case (true, false):
                                                .read
                                        case (false, true):
                                                .write
                                        default:
                                                .read
                                        }
                                    },
                                    set: {
                                        switch $0 {
                                        case .readAndWrite:
                                            relaySettings.read = true
                                            relaySettings.write = true
                                        case .read:
                                            relaySettings.read = true
                                            relaySettings.write = false
                                        case .write:
                                            relaySettings.read = false
                                            relaySettings.write = true
                                        }
                                    }
                                )
                                switch appState.relayState(relayURLString: relaySettings.relayURLString) {
                                case .connected:
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.green)
                                case .connecting:
                                    Image(systemName: "hourglass.circle")
                                        .foregroundStyle(.yellow)
                                case .error:
                                    Image(systemName: "x.circle.fill")
                                        .foregroundStyle(.red)
                                case .notConnected, .none:
                                    Image(systemName: "pause.circle")
                                        .foregroundStyle(.red)
                                }
                                Picker(relaySettings.relayURLString, selection: relayMarkerBinding) {
                                    ForEach(RelayOption.allCases, id: \.self) { option in
                                        Text(option.localizedString)
                                    }
                                }
                                .pickerStyle(.navigationLink)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        appState.removeRelaySettings(relaySettings: relaySettings)
                                    } label: {
                                        Label(String(localized: "Delete", comment: "Label indicating button will delete item."), systemImage: "trash")
                                    }
                                }
                            }
                        }

                        HStack {
                            TextField(String(localized: "wss://relay.example.com", comment: "Example URL of a Nostr relay address."), text: $newRelay)
                                .textContentType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onReceive(Just(newRelay)) { newValue in
                                    let filtered = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    newRelay = filtered

                                    if filtered.isEmpty {
                                        return
                                    }

                                    validatedRelayURL = try? validateRelayURLString(filtered)
                                }

                            Button(
                                action: {
                                    if let validatedRelayURL, canAddRelay {
                                        appState.addRelay(relayURL: validatedRelayURL)
                                        newRelay = ""
                                    }
                                },
                                label: {
                                    Image(systemName: "plus.circle")
                                }
                            )
                            .disabled(!canAddRelay)
                        }
                    }
                },
                header: {
                    Text("Relays", comment: "Settings section for relay management.")
                },
                footer: {
                    Text("Relay settings are saved locally to this device. Authenticated relays and publishing relay lists are not yet supported.", comment: "Relay settings footer text explaining where relay settings are stored and the limitations of relay connections.")
                }
            )
        }
    }

    var canAddRelay: Bool {
        guard let validatedRelayURL, let relaySettingsList = appState.appSettings?.activeProfile?.profileSettings?.relayPoolSettings?.relaySettingsList, !relaySettingsList.contains(where: { $0.relayURLString == validatedRelayURL.absoluteString }) else {
            return false
        }
        return true
    }
}

enum RelayOption: CaseIterable {
    case read
    case write
    case readAndWrite

    var localizedString: String {
        switch self {
        case .read:
            String(localized: "Read", comment: "Picker label to specify preference of only reading from a relay.")
        case .write:
            String(localized: "Write", comment: "Picker label to specify preference of only writing to a relay.")
        case .readAndWrite:
            String(localized: "Read and Write", comment: "Picker label to specify preference of reading from and writing to a relay.")
        }
    }
}
