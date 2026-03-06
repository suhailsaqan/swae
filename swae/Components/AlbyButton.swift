//
//  AlbyButton.swift
//  swae
//
//  Created by Suhail Saqan on 3/7/25.
//


import SwiftUI

struct AlbyButton: View {
    let action: () -> ()
    
    @Environment(\.colorScheme) var colorScheme
    
    init(action: @escaping () -> ()) {
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            action()
        }) {
            HStack {
                Image("alby")
                
                Text("Connect to Alby Wallet", comment:  "Button to attach an Alby Wallet, a service that provides a Lightning wallet for zapping sats. Alby is the name of the service and should not be translated.")
                    .padding()
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            .foregroundColor(.black)
            .background {
                RoundedRectangle(cornerRadius: 12)
//                    .fill(AlbyGradient, strokeBorder: colorScheme == .light ? .black.opacity(0.2) : .white, lineWidth: 1)
            }
        }
    }
}
