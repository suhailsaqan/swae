//
//  String+Extensions.swift
//  swae
//
//  Created by Suhail Saqan on 8/3/24.
//

import Foundation

extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }

    var trimmedOrNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        } else {
            return trimmed
        }
    }
}
