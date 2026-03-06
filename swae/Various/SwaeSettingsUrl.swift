import Foundation

class SwaeSettingsWebBrowser: Codable {
    var home: String?
}

class SwaeSettingsSrt: Codable {
    var latency: Int32?
    var adaptiveBitrateEnabled: Bool?
    var dnsLookupStrategy: SettingsDnsLookupStrategy?
}

class SwaeSettingsUrlStreamVideo: Codable {
    var resolution: SettingsStreamResolution?
    var fps: Int?
    var bitrate: UInt32?
    var codec: SettingsStreamCodec?
    var bFrames: Bool?
    var maxKeyFrameInterval: Int32?
}

class SwaeSettingsUrlStreamAudio: Codable {
    var bitrate: Int?
}

class SwaeSettingsUrlStreamObs: Codable {
    var webSocketUrl: String
    var webSocketPassword: String

    init(webSocketUrl: String, webSocketPassword: String) {
        self.webSocketUrl = webSocketUrl
        self.webSocketPassword = webSocketPassword
    }
}

class SwaeSettingsUrlStreamTwitch: Codable {
    var channelName: String
    var channelId: String

    init(channelName: String, channelId: String) {
        self.channelName = channelName
        self.channelId = channelId
    }
}

class SwaeSettingsUrlStreamKick: Codable {
    var channelName: String

    init(channelName: String) {
        self.channelName = channelName
    }
}

class SwaeSettingsUrlStream: Codable {
    var name: String
    var url: String
    // periphery:ignore
    var enabled: Bool?
    var selected: Bool?
    var video: SwaeSettingsUrlStreamVideo?
    var audio: SwaeSettingsUrlStreamAudio?
    var srt: SwaeSettingsSrt?
    var obs: SwaeSettingsUrlStreamObs?
    var twitch: SwaeSettingsUrlStreamTwitch?
    var kick: SwaeSettingsUrlStreamKick?

    init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

class SwaeSettingsButton: Codable {
    var type: SettingsQuickButtonType
    var enabled: Bool?

    init(type: SettingsQuickButtonType) {
        self.type = type
    }
}

class SwaeQuickButtons: Codable {
    var twoColumns: Bool?
    var showName: Bool?
    var enableScroll: Bool?
    // Use "buttons" to enable buttons after disabling all.
    var disableAllButtons: Bool?
    var buttons: [SwaeSettingsButton]?
}

class SwaeSettingsRemoteControlServerRelay: Codable, ObservableObject {
    var enabled: Bool
    var baseUrl: String
    var bridgeId: String
}

class SwaeSettingsRemoteControlAssistant: Codable {
    var enabled: Bool
    var port: UInt16
    var relay: SwaeSettingsRemoteControlServerRelay?
}

class SwaeSettingsRemoteControlStreamer: Codable {
    var enabled: Bool
    var url: String
}

class SwaeSettingsRemoteControl: Codable {
    var assistant: SwaeSettingsRemoteControlAssistant?
    var streamer: SwaeSettingsRemoteControlStreamer?
    var password: String
}

class SwaeSettingsUrl: Codable {
    // The last enabled stream will be selected (if any).
    var streams: [SwaeSettingsUrlStream]?
    var quickButtons: SwaeQuickButtons?
    var webBrowser: SwaeSettingsWebBrowser?
    var remoteControl: SwaeSettingsRemoteControl?

    func toString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try String.fromUtf8(data: encoder.encode(self))
    }

    static func fromString(query: String) throws -> SwaeSettingsUrl {
        let query = try JSONDecoder().decode(
            SwaeSettingsUrl.self,
            from: query.data(using: .utf8)!
        )
        for stream in query.streams ?? [] {
            if let message = isValidUrl(url: cleanUrl(url: stream.url)) {
                throw message
            }
            if let srt = stream.srt {
                if let latency = srt.latency {
                    if latency < 0 {
                        throw "Negative SRT latency"
                    }
                }
            }
            if let obs = stream.obs {
                if let message = isValidWebSocketUrl(url: cleanUrl(url: obs.webSocketUrl)) {
                    throw message
                }
            }
        }
        return query
    }
}
