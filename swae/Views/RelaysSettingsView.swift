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
            if let relayPoolSettings = appState.relayPoolSettings {
                Section {
                    ForEach(relayPoolSettings.relaySettingsList, id: \.self) { relaySettings in
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
                        
                        HStack(spacing: 12) {
                            // Status indicator
                            statusIcon(for: appState.relayState(relayURLString: relaySettings.relayURLString))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cleanRelayURL(relaySettings.relayURLString))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Text(relayMarkerBinding.wrappedValue.localizedString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Navigate to picker
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                appState.removeRelaySettings(relaySettings: relaySettings)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Picker("Mode", selection: relayMarkerBinding) {
                                ForEach(RelayOption.allCases, id: \.self) { option in
                                    Label(option.localizedString, systemImage: option.iconName)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Connected Relays")
                } footer: {
                    Text("Relays are servers that store and distribute your content across the Nostr network.")
                }

                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.purple)
                            .font(.system(size: 20))
                        
                        TextField("wss://relay.example.com", text: $newRelay)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .onReceive(Just(newRelay)) { newValue in
                                let filtered = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                newRelay = filtered

                                if filtered.isEmpty {
                                    validatedRelayURL = nil
                                    return
                                }

                                validatedRelayURL = try? validateRelayURLString(filtered)
                            }
                            .onSubmit {
                                if let validatedRelayURL, canAddRelay {
                                    appState.addRelay(relayURL: validatedRelayURL)
                                    newRelay = ""
                                }
                            }
                        
                        if canAddRelay {
                            Button(action: {
                                if let validatedRelayURL {
                                    appState.addRelay(relayURL: validatedRelayURL)
                                    newRelay = ""
                                }
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 24))
                            }
                        }
                    }
                } header: {
                    Text("Add Relay")
                } footer: {
                    Text("Enter a relay URL starting with wss:// to add it to your list. Settings are saved locally on this device.")
                }
            }
        }
        .navigationTitle("Relays")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func statusIcon(for state: Relay.State?) -> some View {
        Group {
            switch state {
            case .connected:
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
            case .connecting:
                Image(systemName: "circle.fill")
                    .foregroundStyle(.yellow)
            case .error:
                Image(systemName: "circle.fill")
                    .foregroundStyle(.red)
            case .notConnected, .none:
                Image(systemName: "circle.fill")
                    .foregroundStyle(.gray)
            }
        }
        .font(.system(size: 12))
    }
    
    func cleanRelayURL(_ url: String) -> String {
        return url.replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
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
    
    var iconName: String {
        switch self {
        case .read:
            "arrow.down.circle"
        case .write:
            "arrow.up.circle"
        case .readAndWrite:
            "arrow.up.arrow.down.circle"
        }
    }
}
