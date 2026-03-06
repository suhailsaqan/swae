import Foundation

// MARK: - Protobuf wire format helpers

// Protobuf field encoding: (fieldNumber << 3) | wireType
// Wire types: 0 = varint, 2 = length-delimited

enum GoProProtobuf {
    // MARK: - Encoding

    static func encodeVarint(_ value: UInt64) -> Data {
        var data = Data()
        var v = value
        while v > 0x7F {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
        return data
    }

    static func encodeField(fieldNumber: Int, wireType: Int, value: Data) -> Data {
        var data = Data()
        let tag = UInt64((fieldNumber << 3) | wireType)
        data.append(encodeVarint(tag))
        if wireType == 2 {
            data.append(encodeVarint(UInt64(value.count)))
        }
        data.append(value)
        return data
    }

    static func encodeString(fieldNumber: Int, value: String) -> Data {
        return encodeField(fieldNumber: fieldNumber, wireType: 2, value: Data(value.utf8))
    }

    static func encodeBool(fieldNumber: Int, value: Bool) -> Data {
        return encodeField(fieldNumber: fieldNumber, wireType: 0, value: encodeVarint(value ? 1 : 0))
    }

    static func encodeInt32(fieldNumber: Int, value: Int32) -> Data {
        return encodeField(fieldNumber: fieldNumber, wireType: 0, value: encodeVarint(UInt64(bitPattern: Int64(value))))
    }

    static func encodeEnum(fieldNumber: Int, value: Int) -> Data {
        return encodeField(fieldNumber: fieldNumber, wireType: 0, value: encodeVarint(UInt64(value)))
    }

    // MARK: - Decoding

    static func decodeVarint(data: Data, offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    struct ProtoField {
        let fieldNumber: Int
        let wireType: Int
        let data: Data
    }

    static func decodeFields(data: Data) -> [ProtoField] {
        var fields: [ProtoField] = []
        var offset = 0
        while offset < data.count {
            guard let tag = decodeVarint(data: data, offset: &offset) else { break }
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)
            switch wireType {
            case 0: // varint
                guard let value = decodeVarint(data: data, offset: &offset) else { break }
                var varintData = Data()
                var v = value
                repeat {
                    varintData.append(UInt8(v & 0xFF))
                    v >>= 8
                } while v > 0
                fields.append(ProtoField(fieldNumber: fieldNumber, wireType: wireType, data: varintData))
            case 2: // length-delimited
                guard let length = decodeVarint(data: data, offset: &offset) else { break }
                let end = offset + Int(length)
                guard end <= data.count else { break }
                fields.append(ProtoField(fieldNumber: fieldNumber, wireType: wireType, data: data[offset ..< end]))
                offset = end
            default:
                return fields // Unknown wire type, stop parsing
            }
        }
        return fields
    }

    static func getVarintValue(field: ProtoField) -> UInt64 {
        var offset = 0
        // Re-encode from stored bytes
        var result: UInt64 = 0
        for i in 0 ..< min(field.data.count, 8) {
            result |= UInt64(field.data[field.data.startIndex + i]) << (i * 8)
        }
        return result
    }

    // MARK: - GoPro BLE Message Framing

    /// Wraps a protobuf payload with the GoPro BLE header (feature ID + action ID)
    /// and splits into MTU-sized packets.
    static func frameMessage(featureId: UInt8, actionId: UInt8, payload: Data, mtu: Int = 20) -> [Data] {
        var message = Data([featureId, actionId])
        message.append(payload)
        return splitIntoPackets(message: message, mtu: mtu)
    }

    /// Wraps a TLV command into BLE packets.
    static func frameTlvCommand(command: Data, mtu: Int = 20) -> [Data] {
        return splitIntoPackets(message: command, mtu: mtu)
    }

    private static func splitIntoPackets(message: Data, mtu: Int) -> [Data] {
        var packets: [Data] = []
        let totalLength = message.count
        if totalLength <= 0x1F, totalLength + 1 <= mtu {
            // Single packet with 5-bit general header: [length, ...message...]
            // Bits 6-5 = 00 (general), bits 0-4 = length
            var packet = Data([UInt8(totalLength & 0x1F)])
            packet.append(message)
            packets.append(packet)
        } else if totalLength <= 0x1FFF {
            // 13-bit extended header
            // First byte: bits 6-5 = 01, bits 0-4 = high 5 bits of length
            // Second byte: low 8 bits of length
            let headerByte = UInt8(0x20 | ((totalLength >> 8) & 0x1F))
            let lengthLow = UInt8(totalLength & 0xFF)
            var firstPacket = Data([headerByte, lengthLow])
            let firstPayloadSize = min(mtu - 2, totalLength)
            firstPacket.append(message[0 ..< firstPayloadSize])
            packets.append(firstPacket)
            var offset = firstPayloadSize
            while offset < totalLength {
                var contPacket = Data([0x80])
                let chunkSize = min(mtu - 1, totalLength - offset)
                contPacket.append(message[offset ..< offset + chunkSize])
                packets.append(contPacket)
                offset += chunkSize
            }
        } else {
            // 16-bit extended header
            let headerByte: UInt8 = 0x40 // bits 6-5 = 10
            var firstPacket = Data([headerByte, UInt8((totalLength >> 8) & 0xFF), UInt8(totalLength & 0xFF)])
            let firstPayloadSize = min(mtu - 3, totalLength)
            firstPacket.append(message[0 ..< firstPayloadSize])
            packets.append(firstPacket)
            var offset = firstPayloadSize
            while offset < totalLength {
                var contPacket = Data([0x80])
                let chunkSize = min(mtu - 1, totalLength - offset)
                contPacket.append(message[offset ..< offset + chunkSize])
                packets.append(contPacket)
                offset += chunkSize
            }
        }
        return packets
    }

    /// Reassembles a multi-packet BLE response into a single message.
    static func reassemble(packets: [Data]) -> Data? {
        guard let first = packets.first, !first.isEmpty else { return nil }
        let header = first[0]
        guard header & 0x20 != 0 else { return nil }
        let headerLen = Int(header & 0x1F)
        var startOffset: Int
        if headerLen == 0 {
            // Empty message
            return Data()
        } else if headerLen <= first.count - 1 {
            // Single packet: payload starts at index 1
            startOffset = 1
        } else {
            startOffset = 1 + headerLen
        }
        var result = Data()
        if startOffset < first.count {
            result.append(first[startOffset...])
        }
        for packet in packets.dropFirst() {
            guard !packet.isEmpty else { continue }
            // Continuation packets: skip first byte (0x80)
            if packet[0] & 0x80 != 0 {
                result.append(packet[1...])
            }
        }
        return result
    }

    // MARK: - GoPro-specific message builders

    static func buildRequestStartScan() -> Data {
        // RequestStartScan is an empty message — serializes to zero bytes
        return Data()
    }

    static func buildRequestGetApEntries(startIndex: Int32, maxEntries: Int32, scanId: Int32) -> Data {
        var payload = Data()
        payload.append(encodeInt32(fieldNumber: 1, value: startIndex))
        payload.append(encodeInt32(fieldNumber: 2, value: maxEntries))
        payload.append(encodeInt32(fieldNumber: 3, value: scanId))
        return payload
    }

    static func buildRequestConnectNew(ssid: String, password: String) -> Data {
        var payload = Data()
        payload.append(encodeString(fieldNumber: 1, value: ssid))
        payload.append(encodeString(fieldNumber: 2, value: password))
        return payload
    }

    static func buildRequestConnect(ssid: String) -> Data {
        var payload = Data()
        payload.append(encodeString(fieldNumber: 1, value: ssid))
        return payload
    }

    static func buildRequestSetLiveStreamMode(
        url: String,
        encode: Bool = false,
        windowSize: GoProWindowSize = .r1080p,
        minimumBitrate: Int32 = 4000,
        maximumBitrate: Int32 = 8000,
        startingBitrate: Int32 = 6000
    ) -> Data {
        var payload = Data()
        payload.append(encodeString(fieldNumber: 1, value: url))
        payload.append(encodeBool(fieldNumber: 2, value: encode))
        payload.append(encodeEnum(fieldNumber: 3, value: windowSize.rawValue))
        payload.append(encodeInt32(fieldNumber: 7, value: minimumBitrate))
        payload.append(encodeInt32(fieldNumber: 8, value: maximumBitrate))
        payload.append(encodeInt32(fieldNumber: 9, value: startingBitrate))
        return payload
    }

    static func buildRequestGetLiveStreamStatus(registerForUpdates: Bool = true) -> Data {
        var payload = Data()
        if registerForUpdates {
            // Register for: STATUS(1), ERROR(2), MODE(3), BITRATE(4)
            // These are repeated EnumRegisterLiveStreamStatus values
            payload.append(encodeEnum(fieldNumber: 1, value: 1)) // STATUS
            payload.append(encodeEnum(fieldNumber: 1, value: 2)) // ERROR
            payload.append(encodeEnum(fieldNumber: 1, value: 3)) // MODE
            payload.append(encodeEnum(fieldNumber: 1, value: 4)) // BITRATE
        }
        return payload
    }

    // MARK: - Shutter commands (TLV, not protobuf)

    static let shutterOn = Data([0x03, 0x01, 0x01, 0x01])
    static let shutterOff = Data([0x03, 0x01, 0x01, 0x00])

    // MARK: - Scan result parsing

    static func parseScanEntries(data: Data) -> [GoProScanEntry] {
        let fields = decodeFields(data: data)
        var entries: [GoProScanEntry] = []
        // Field 3 = repeated ScanEntry (length-delimited nested messages)
        for field in fields where field.fieldNumber == 3 && field.wireType == 2 {
            let entryFields = decodeFields(data: field.data)
            var ssid = ""
            var signalBars = 0
            var freqMhz = 0
            var flags = 0
            for ef in entryFields {
                switch ef.fieldNumber {
                case 1: ssid = String(data: ef.data, encoding: .utf8) ?? ""
                case 2: signalBars = Int(getVarintValue(field: ef))
                case 4: freqMhz = Int(getVarintValue(field: ef))
                case 5: flags = Int(getVarintValue(field: ef))
                default: break
                }
            }
            if !ssid.isEmpty {
                entries.append(GoProScanEntry(ssid: ssid, signalStrengthBars: signalBars,
                                             signalFrequencyMhz: freqMhz, flags: flags))
            }
        }
        return entries
    }
}

struct GoProScanEntry {
    let ssid: String
    let signalStrengthBars: Int
    let signalFrequencyMhz: Int
    let flags: Int

    var isConfigured: Bool { flags & 0x02 != 0 }
    var isAssociated: Bool { flags & 0x08 != 0 }
    var requiresAuth: Bool { flags & 0x01 != 0 }
}

enum GoProWindowSize: Int {
    case r480p = 4
    case r720p = 7
    case r1080p = 12
}

enum GoProLiveStreamStatus: Int {
    case idle = 0
    case config = 1
    case ready = 2
    case streaming = 3
    case completeStayOn = 4
    case failedStayOn = 5
    case reconnecting = 6
    case unavailable = 7
    case unknown = -1

    init(rawValue: Int) {
        switch rawValue {
        case 0: self = .idle
        case 1: self = .config
        case 2: self = .ready
        case 3: self = .streaming
        case 4: self = .completeStayOn
        case 5: self = .failedStayOn
        case 6: self = .reconnecting
        case 7: self = .unavailable
        default: self = .unknown
        }
    }
}
