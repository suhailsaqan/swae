//
//  KeyboardObserver.swift
//  swae
//
//  Created by Suhail Saqan on 2/15/25.
//


import SwiftUI
import Combine

class KeyboardObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    
    private var cancellable: AnyCancellable?
    
    init() {
        cancellable = Publishers
            .Merge(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                    .map { notification -> CGFloat in
                        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
                        return keyboardFrame.height
                    },
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
                    .map { _ in CGFloat(0) }
            )
            .assign(to: \.keyboardHeight, on: self)
    }
}
