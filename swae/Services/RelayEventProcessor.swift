//
//  RelayEventProcessor.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import Combine
import Foundation
import NostrSDK

/// Placeholder for relay event processing.
///
/// Event processing is handled by AppState's RelayDelegate conformance.
/// This class exists to avoid breaking the reference held by AppState.
/// It no longer overrides the relay pool delegate, which AppState needs
/// for state-change handling and auto-reconnection.
class RelayEventProcessor: ObservableObject {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }
}
