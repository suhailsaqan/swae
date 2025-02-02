//
//  Item.swift
//  swae
//
//  Created by Suhail Saqan on 1/25/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
