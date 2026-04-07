//
//  BIP39.swift
//  swae
//
//  BIP39 mnemonic generation from entropy.
//  Spec: https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
//
//  Supports 128-bit entropy (12 words) and 256-bit entropy (24 words).
//  The wordlist is loaded from the bundled bip39-english.txt file.
//

import CryptoKit
import Foundation

enum BIP39 {

    enum BIP39Error: Error, LocalizedError {
        case invalidEntropyLength
        case invalidMnemonic
        case wordlistNotFound

        var errorDescription: String? {
            switch self {
            case .invalidEntropyLength:
                return "Entropy must be 16 bytes (128-bit) or 32 bytes (256-bit)"
            case .invalidMnemonic:
                return "Invalid mnemonic phrase"
            case .wordlistNotFound:
                return "BIP39 wordlist file not found in bundle"
            }
        }
    }

    // MARK: - Wordlist

    /// Lazily loaded BIP39 English wordlist (2048 words)
    private static let wordlist: [String] = {
        guard let url = Bundle.main.url(forResource: "bip39-english", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("BIP39 wordlist not found in bundle. Add bip39-english.txt to the target.")
        }
        let words = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
        assert(words.count == 2048, "BIP39 wordlist must have exactly 2048 words")
        return words
    }()

    // MARK: - Mnemonic Generation

    /// Generates a BIP39 mnemonic from entropy bytes.
    /// - Parameter entropy: 16 bytes → 12 words, or 32 bytes → 24 words
    /// - Returns: Space-separated mnemonic words
    static func mnemonicFromEntropy(_ entropy: Data) throws -> String {
        guard entropy.count == 16 || entropy.count == 32 else {
            throw BIP39Error.invalidEntropyLength
        }

        // SHA256 hash of entropy for checksum
        let hash = Array(SHA256.hash(data: entropy))

        // Checksum length = entropy_bits / 32
        let entropyBits = entropy.count * 8
        let checksumBits = entropyBits / 32

        // Build bit array: entropy bits + checksum bits
        var bits = [Bool]()
        bits.reserveCapacity(entropyBits + checksumBits)

        for byte in entropy {
            for i in (0..<8).reversed() {
                bits.append((byte >> i) & 1 == 1)
            }
        }
        for i in 0..<checksumBits {
            let byteIndex = i / 8
            let bitIndex = 7 - (i % 8)
            bits.append((hash[byteIndex] >> bitIndex) & 1 == 1)
        }

        // Split into 11-bit groups → word indices
        let wordCount = bits.count / 11
        var words = [String]()
        words.reserveCapacity(wordCount)

        for i in 0..<wordCount {
            var index = 0
            for j in 0..<11 {
                if bits[i * 11 + j] {
                    index |= (1 << (10 - j))
                }
            }
            words.append(wordlist[index])
        }

        return words.joined(separator: " ")
    }

    // MARK: - Validation

    /// Validates a BIP39 mnemonic by checking word count, words, and checksum.
    static func validateMnemonic(_ mnemonic: String) -> Bool {
        let words = mnemonic.split(separator: " ").map(String.init)
        guard words.count == 12 || words.count == 24 else { return false }

        let wordSet = Set(wordlist)
        for word in words {
            guard wordSet.contains(word) else { return false }
        }

        // Convert words back to bit array
        var bits = [Bool]()
        for word in words {
            guard let index = wordlist.firstIndex(of: word) else { return false }
            for j in (0..<11).reversed() {
                bits.append((index >> j) & 1 == 1)
            }
        }

        // Split entropy and checksum
        let checksumBits = words.count == 12 ? 4 : 8
        let entropyBitCount = bits.count - checksumBits

        // Reconstruct entropy bytes
        var entropy = Data()
        for i in stride(from: 0, to: entropyBitCount, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 {
                if bits[i + j] { byte |= (1 << (7 - j)) }
            }
            entropy.append(byte)
        }

        // Verify checksum
        let hash = Array(SHA256.hash(data: entropy))
        for i in 0..<checksumBits {
            let byteIndex = i / 8
            let bitIndex = 7 - (i % 8)
            let expected = (hash[byteIndex] >> bitIndex) & 1 == 1
            if bits[entropyBitCount + i] != expected { return false }
        }

        return true
    }
}
