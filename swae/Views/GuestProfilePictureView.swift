//
//  GuestProfilePictureView.swift
//  swae
//
//  Created by Suhail Saqan on 2/1/25.
//

import SwiftUI

struct GuestProfilePictureView: View {
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: "person.crop.circle")
            .resizable()
            .scaledToFit()
            .frame(width: size)
            .clipShape(.circle)
    }
}

#Preview {
    GuestProfilePictureView()
}
