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
