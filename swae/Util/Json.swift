//
//  Json.swift
//  swae
//
//  Created by Suhail Saqan on 3/8/25.
//

import Foundation

func decodeJson<T: Decodable>(_ val: String) -> T? {
    return try? JSONDecoder().decode(T.self, from: Data(val.utf8))
}

func encode_json<T: Encodable>(_ val: T) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return (try? encode_json_data(val)).map { String(decoding: $0, as: UTF8.self) }
}

func encode_json_data<T: Encodable>(_ val: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return try encoder.encode(val)
}
