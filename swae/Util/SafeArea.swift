//
//  SafeArea.swift
//  swae
//
//  Created by Suhail Saqan on 2/26/25.
//

import SwiftUI

let swae_app: UIApplication = UIApplication.shared

func getSafeAreaBottom() -> CGFloat {
    guard let scene = swae_app.connectedScenes.first as? UIWindowScene else{return .zero}
    guard let bottomSafeArea = scene.windows.first?.safeAreaInsets.bottom else{return .zero}
    return bottomSafeArea
}
