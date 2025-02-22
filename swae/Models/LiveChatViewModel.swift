//
//  ViewModel.swift
//  swae
//
//  Created by Suhail Saqan on 2/13/25.
//

import NostrSDK
import Combine

class ViewModel: ObservableObject, EventCreating {
    // If you need to set appState later (because it isn’t available in the initializer)
    @Published var appState: AppState!
    
    @Published var messageText: String = ""
    let liveActivitiesEvent: LiveActivitiesEvent
    
    init(liveActivitiesEvent: LiveActivitiesEvent) {
        self.liveActivitiesEvent = liveActivitiesEvent
    }
    
    func saveLiveChatMessageEvent() -> Bool {
        // Make sure messageText is not empty.
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // Make sure we have an appState keypair.
        guard let keypair = appState?.keypair else {
            print("no keypair")
            return false
        }
        // Make sure liveActivitiesEvent.identifier is valid (not nil or empty).
        guard let identifier = liveActivitiesEvent.identifier, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Invalid identifier")
            return false
        }

        do {
            print(messageText, liveActivitiesEvent.pubkey, liveActivitiesEvent.id)
            let liveChatMessageEvent = try liveChatMessageEvent(
                content: messageText,
                liveEventPubKey: liveActivitiesEvent.pubkey,
                d: identifier,
                relay: "wss://relay.damus.io",
                signedBy: keypair
            )
            
            if let liveActivitiesEventCoordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value {
                print("liveActivitiesEventCoordinates:", liveActivitiesEventCoordinates)
                // Publish the event.
                appState.relayWritePool.publishEvent(liveChatMessageEvent)
                return true
            }
        } catch {
            print("Unable to save event: \(error)")
        }
        return false
    }
}
