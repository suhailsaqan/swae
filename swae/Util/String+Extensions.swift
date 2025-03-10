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
    
    func hexDecoded() -> Data? {
        // Handle empty strings
        guard !isEmpty else { return Data() }
        
        // Remove "0x" prefix if present
        let hexString = hasPrefix("0x") ? String(dropFirst(2)) : self
        
        // Ensure even length
        let paddedHex = hexString.count % 2 == 0 ? hexString : "0" + hexString
        
        // Fast lookup table for hex digit values
        let hexValues: [UInt8] = [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 0-15
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 16-31
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 32-47
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0, 0, 0, 0, // 48-63 ('0'-'9')
            0, 10, 11, 12, 13, 14, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 64-79 ('A'-'F')
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 80-95
            0, 10, 11, 12, 13, 14, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 96-111 ('a'-'f')
        ]
        
        var data = Data(capacity: paddedHex.count / 2)
        
        let utf8 = paddedHex.utf8
        var index = utf8.startIndex
        
        while index < utf8.endIndex {
            // Get ASCII value of the first character
            let firstChar = utf8[index]
            // Ensure it's a valid hex character
            guard firstChar < 128, hexValues[Int(firstChar)] > 0 || (firstChar >= 48 && firstChar <= 57) else {
                return nil
            }
            
            index = utf8.index(after: index)
            // Get ASCII value of the second character
            let secondChar = utf8[index]
            // Ensure it's a valid hex character
            guard secondChar < 128, hexValues[Int(secondChar)] > 0 || (secondChar >= 48 && secondChar <= 57) else {
                return nil
            }
            
            // Calculate byte value using the lookup table
            let byte = (hexValues[Int(firstChar)] << 4) | hexValues[Int(secondChar)]
            data.append(byte)
            
            index = utf8.index(after: index)
        }
        
        return data
    }
}
