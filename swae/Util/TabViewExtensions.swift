//
//  Tab.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import SwiftUI

extension View {
    @ViewBuilder
    func setupTab(_ tab: ScreenTabs) -> some View {
        self
            .tag(tab)
            .toolbar(.hidden, for: .tabBar)
    }
}
