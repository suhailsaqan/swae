//
//  CustomVideoPlayer.swift
//  swae
//
//  Created by Suhail Saqan on 1/25/25.
//

import AVKit
import SwiftUI

struct CustomVideoPlayer: UIViewControllerRepresentable {
    var player: AVPlayer
    @Binding var videoSize: CGSize

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false

        // Observe video size
        if let item = player.currentItem {
            item.addObserver(context.coordinator, forKeyPath: "presentationSize", options: .new, context: nil)
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: CustomVideoPlayer

        init(_ parent: CustomVideoPlayer) {
            self.parent = parent
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "presentationSize",
               let item = object as? AVPlayerItem,
               let newSize = change?[.newKey] as? CGSize {
                DispatchQueue.main.async {
                    self.parent.videoSize = newSize
                }
            }
        }
    }
}
