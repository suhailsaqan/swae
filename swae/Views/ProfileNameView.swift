//
//  ProfileNameView.swift
//  swae
//
//  Created by Suhail Saqan on 2/18/25.
//


import NostrSDK
import SwiftUI

struct ProfileNameView: View {
    var publicKeyHex: String?

    @EnvironmentObject var appState: AppState

    var body: some View {
        Text(Utilities.shared.profileName(publicKeyHex: publicKeyHex, appState: appState))
    }
}
