//
//  MiniPlayerSupport.swift
//  swae
//
//  Protocol for controllers that support mini player behavior
//

import Foundation

/// Protocol for view controllers that can respond to chat scroll requests for mini player
protocol MiniPlayerSupport: AnyObject {
    /// Called when chat controller wants to request mini player mode
    /// - Parameter mini: true to minimize, false to expand
    func chatControllerRequestMiniPlayer(_ mini: Bool)
}
