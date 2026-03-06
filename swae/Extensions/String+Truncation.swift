//
//  String+Truncation.swift
//  swae
//
//  String extensions for username truncation
//

import Foundation

extension String {
    /// Truncates username with ellipsis, preserving start
    func truncatedUsername(maxLength: Int = ChatDisplayConstants.maxUsernameLength) -> String {
        guard count > maxLength else { return self }
        return String(prefix(maxLength - 1)) + "…"
    }
    
    /// Smart truncation that tries to break at word boundaries
    func smartTruncatedUsername(maxLength: Int = ChatDisplayConstants.maxUsernameLength) -> String {
        guard count > maxLength else { return self }
        
        let truncated = String(prefix(maxLength - 1))
        
        // Try to find last space to break cleanly
        if let lastSpace = truncated.lastIndex(of: " "),
           truncated.distance(from: truncated.startIndex, to: lastSpace) > maxLength / 2 {
            return String(truncated[..<lastSpace]) + "…"
        }
        
        // Check for common separators
        for separator in ["|", "-", "_", "."] {
            if let lastSep = truncated.lastIndex(of: Character(separator)),
               truncated.distance(from: truncated.startIndex, to: lastSep) > maxLength / 2 {
                return String(truncated[..<lastSep]).trimmingCharacters(in: .whitespaces) + "…"
            }
        }
        
        return truncated + "…"
    }
}
