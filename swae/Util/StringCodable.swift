//
//  StringCodable.swift
//  swae
//
//  Created by Suhail Saqan on 4/1/25.
//


import Foundation

protocol StringCodable {
    init?(from string: String)
    func to_string() -> String
}
