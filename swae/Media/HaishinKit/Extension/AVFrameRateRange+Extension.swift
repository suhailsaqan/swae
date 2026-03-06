//
//  AVFrameRateRange+Extension.swift
//  swae
//
//  Created by Suhail Saqan on 8/21/25.
//

import AVFoundation
import Foundation

extension AVFrameRateRange {
    func contains(frameRate: Float64) -> Bool {
        (minFrameRate ... maxFrameRate) ~= frameRate
    }
}
