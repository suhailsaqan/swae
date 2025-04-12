//
//  StringUtil.swift
//  swae
//
//  Created by Suhail Saqan on 2/24/25.
//

import Foundation

extension String {
    /// Returns a copy of the String truncated to maxLength and "..." ellipsis appended to the end,
    /// or if the String does not exceed maxLength, the String itself is returned without truncation or added ellipsis.
    func truncate(maxLength: Int) -> String {
        guard count > maxLength else {
            return self
        }

        return self[...self.index(self.startIndex, offsetBy: maxLength - 1)] + "..."
    }
}

extension AttributedString {
    /// Returns a copy of the AttributedString truncated to maxLength and "..." ellipsis appended to the end,
    /// or if the AttributedString does not exceed maxLength, nil is returned.
    func truncateOrNil(maxLength: Int) -> AttributedString? {
        let nsAttributedString = NSAttributedString(self)
        if nsAttributedString.length < maxLength { return nil }

        let range = NSRange(location: 0, length: maxLength)
        let truncatedAttributedString = nsAttributedString.attributedSubstring(from: range)

        return AttributedString(truncatedAttributedString) + "..."
    }
}

func pluralize(_ word: String, count: Int64) -> String {
    guard count != 1 else { return word }
    
    let irregularPlurals: [String: String] = [
        "child": "children"
        /// ...
    ]
    
    if let irregular = irregularPlurals[word.lowercased()] {
        return irregular
    }
    
    if word.hasSuffix("y") && !["a", "e", "i", "o", "u"].contains(word[word.index(before: word.endIndex)].lowercased()) {
        return word.dropLast() + "ies"
    } else if word.hasSuffix("s") || word.hasSuffix("x") || word.hasSuffix("z") || word.hasSuffix("ch") || word.hasSuffix("sh") {
        return word + "es"
    } else {
        return word + "s"
    }
}

func toMSats(_ msat: Int64) -> String {
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    numberFormatter.minimumFractionDigits = 0
    numberFormatter.maximumFractionDigits = 3
    numberFormatter.roundingMode = .down

    let sats = NSNumber(value: (Double(msat) / 1000.0))
    let formattedSats = numberFormatter.string(from: sats) ?? sats.stringValue

    return String(formattedSats)
}
