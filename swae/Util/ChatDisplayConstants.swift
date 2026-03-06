//
//  ChatDisplayConstants.swift
//  swae
//
//  Constants for chat display limits to prevent overflow and abuse
//

import Foundation
import UIKit

struct ChatDisplayConstants {
    // Username limits
    static let maxUsernameLength = 20
    static let maxUsernameDisplayWidth: CGFloat = 120  // Points
    
    // Message limits
    static let maxMessageLines = 4
    static let maxMessageCharacters = 500
    static let collapsedMessageLines = 2
    
    // Zap display
    static let maxZapAmountDigits = 7  // Up to 9,999,999 sats displayed as-is
    
    // Cell height limits
    static let maxCellHeight: CGFloat = 150
    static let minCellHeight: CGFloat = 44
}
