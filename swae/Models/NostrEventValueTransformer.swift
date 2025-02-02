//
//  NostrEventValueTransformer.swift
//  swae
//
//  Created by Suhail Saqan on 8/22/24.
//

import Foundation
import NostrSDK

class NostrEventValueTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass {
        return NostrEvent.self
    }

    override class func allowsReverseTransformation() -> Bool {
        return true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let nostrEvent = value as? NostrEvent else {
            return nil
        }

        return try? JSONEncoder().encode(nostrEvent)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else {
            return nil
        }

        let jsonDecoder = JSONDecoder()

        guard let eventKindMapper = try? jsonDecoder.decode(EventKindMapper.self, from: data) else {
            return nil
        }

        return try? jsonDecoder.decode(eventKindMapper.classForKind, from: data)
    }

    static func register() {
        ValueTransformer.setValueTransformer(
            NostrEventValueTransformer(), forName: .init("NostrEventValueTransformer"))
    }
}

private struct EventKindMapper: Decodable {
    let kind: EventKind

    enum CodingKeys: CodingKey {
        case kind
    }

    var classForKind: NostrEvent.Type {
        kind.classForKind
    }
}
