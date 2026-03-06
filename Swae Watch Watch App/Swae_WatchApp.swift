//
//  Swae_WatchApp.swift
//  Swae Watch Watch App
//
//  Created by Suhail Saqan on 8/20/25.
//

import SwiftUI

@main
struct SwaeWatchApp: App {
    @StateObject var model: Model
    static var globalModel: Model?

    init() {
        SwaeWatchApp.globalModel = Model()
        _model = StateObject(wrappedValue: SwaeWatchApp.globalModel!)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
        }
    }
}
