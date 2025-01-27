//
//  AppSettings.swift
//  gibbe
//
//  Created by Suhail on 10/08/24.
//

import SwiftData

@Model
final class AppSettings {

    var activeProfile: Profile?

    init(activeProfile: Profile = Profile()) {
        self.activeProfile = activeProfile
    }
}
