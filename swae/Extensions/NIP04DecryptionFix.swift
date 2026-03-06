//
//  NIP04DecryptionFix.swift
//  swae
//
//  Fix for NIP-04 decryption with x-only public keys
//  This tries both 0x02 (even y) and 0x03 (odd y) prefixes
//

import CommonCrypto
import Foundation
import NostrSDK
import secp256k1

/// Helper to decrypt NIP-04 messages with fallback for different y-coordinate prefixes
struct NIP04DecryptionHelper {
    
    /// Attempts to decrypt with both possible y-coordinate prefixes (0x02 and 0x03)
    static func decryptWithFallback(
        encryptedMessage: String,
        senderPublicKey: PublicKey,
        recipientPrivateKey: PrivateKey
    ) throws -> String {
        
        // Try with 0x02 prefix (even y) first - this is the BIP340 standard
        if let result = try? decrypt(
            encryptedMessage: encryptedMessage,
            senderPublicKey: senderPublicKey,
            recipientPrivateKey: recipientPrivateKey,
            useOddY: false
        ) {
            print("✅ NIP04: Decryption succeeded with 0x02 prefix (even y)")
            return result
        }
        
        print("⚠️ NIP04: Decryption failed with 0x02 prefix, trying 0x03 (odd y)")
        
        // If that fails, try with 0x03 prefix (odd y)
        let result = try decrypt(
            encryptedMessage: encryptedMessage,
            senderPublicKey: senderPublicKey,
            recipientPrivateKey: recipientPrivateKey,
            useOddY: true
        )
        print("✅ NIP04: Decryption succeeded with 0x03 prefix (odd y)")
        return result
    }
    
    private static func decrypt(
        encryptedMessage: String,
        senderPublicKey: PublicKey,
        recipientPrivateKey: PrivateKey,
        useOddY: Bool
    ) throws -> String {
        
        // Parse NIP-04 format: base64(encrypted_message)?iv=base64(iv)
        let sections = encryptedMessage.split(separator: "?")
        guard sections.count == 2 else {
            throw NSError(domain: "NIP04", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid format"])
        }
        
        guard let encryptedBase64 = sections.first,
            let encryptedData = Data(base64Encoded: String(encryptedBase64))
        else {
            throw NSError(domain: "NIP04", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid base64"])
        }
        
        guard let ivSection = sections.last,
            ivSection.hasPrefix("iv=")
        else {
            throw NSError(domain: "NIP04", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid IV format"])
        }
        
        let ivBase64 = String(ivSection.dropFirst(3))
        guard let iv = Data(base64Encoded: ivBase64) else {
            throw NSError(domain: "NIP04", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid IV base64"])
        }
        
        // Compute shared secret with specified prefix
        let sharedSecret = try computeSharedSecret(
            privateKey: recipientPrivateKey,
            publicKey: senderPublicKey,
            useOddY: useOddY
        )
        
        // Decrypt using AES-256-CBC
        let decryptedData = try decryptAES256CBC(
            data: encryptedData,
            key: sharedSecret,
            iv: iv
        )
        
        guard let decryptedMessage = String(data: decryptedData, encoding: .utf8) else {
            throw NSError(domain: "NIP04", code: 5, userInfo: [NSLocalizedDescriptionKey: "Decrypted data is not valid UTF-8"])
        }
        
        return decryptedMessage
    }
    
    private static func computeSharedSecret(
        privateKey: PrivateKey,
        publicKey: PublicKey,
        useOddY: Bool
    ) throws -> Data {
        
        let privateKeyBytes = privateKey.dataRepresentation.bytes
        
        // Prepare public key bytes with appropriate prefix
        var publicKeyBytes = publicKey.dataRepresentation.bytes
        publicKeyBytes.insert(useOddY ? 0x03 : 0x02, at: 0)
        
        // Parse public key
        var secp256k1PublicKey = secp256k1_pubkey()
        guard
            secp256k1_ec_pubkey_parse(
                secp256k1.Context.rawRepresentation,
                &secp256k1PublicKey,
                publicKeyBytes,
                publicKeyBytes.count
            ) != 0
        else {
            throw NSError(domain: "NIP04", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid public key"])
        }
        
        // Compute ECDH shared secret
        var sharedSecret = [UInt8](repeating: 0, count: 32)
        guard
            secp256k1_ecdh(
                secp256k1.Context.rawRepresentation,
                &sharedSecret,
                &secp256k1PublicKey,
                privateKeyBytes,
                { (output, x32, _, _) in
                    memcpy(output, x32, 32)
                    return 1
                },
                nil
            ) != 0
        else {
            throw NSError(domain: "NIP04", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to compute shared secret"])
        }
        
        return Data(sharedSecret)
    }
    
    private static func decryptAES256CBC(
        data: Data,
        key: Data,
        iv: Data
    ) throws -> Data {
        
        let aesKey = key.prefix(32)
        let keyBytes = Array(aesKey)
        let ivBytes = Array(iv)
        let dataBytes = Array(data)
        
        let dataLength = dataBytes.count
        let bufferSize = dataLength + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var numBytesDecrypted: size_t = 0
        
        guard keyBytes.count == kCCKeySizeAES256 else {
            throw NSError(domain: "NIP04", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid key size"])
        }
        
        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            keyBytes,
            keyBytes.count,
            ivBytes,
            dataBytes,
            dataLength,
            &buffer,
            bufferSize,
            &numBytesDecrypted
        )
        
        guard status == kCCSuccess else {
            throw NSError(domain: "NIP04", code: 9, userInfo: [NSLocalizedDescriptionKey: "AES decryption failed with status: \(status)"])
        }
        
        return Data(buffer.prefix(numBytesDecrypted))
    }
}
