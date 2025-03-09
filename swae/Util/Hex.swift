//
//  Hex.swift
//  swae
//
//  Created by Suhail Saqan on 3/8/25.
//

import Foundation
import NostrSDK

func hex_decode_id(_ str: String) -> Data? {
    guard str.utf8.count == 64, let decoded = str.hexDecoded() else {
        return nil
    }

    return Data(decoded)
}

//func hex_decode_noteid(_ str: String) -> NoteId? {
//    return hex_decode_id(str).map(NoteId.init)
//}

func hex_decode_pubkey(_ str: String) -> PublicKey? {
    guard let data = hex_decode_id(str) else {
        return nil
    }
    
    return PublicKey(dataRepresentation: data)
}

func hex_decode_privkey(_ str: String) -> PrivateKey? {
    guard let data = hex_decode_id(str) else {
        return nil
    }
    
    return PrivateKey(dataRepresentation: data)
}
