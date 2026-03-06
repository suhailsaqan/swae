/// Migration Baseline Tests
/// These tests establish a baseline for critical functionality before porting Moblin improvements.
/// Run these tests BEFORE and AFTER each migration phase to ensure nothing breaks.

import AVFoundation
@testable import swae
import Testing

// MARK: - Video Dimensions Tests

struct VideoDimensionsSuite {
    @Test
    func landscape16x9() {
        let resolution = CMVideoDimensions(width: 1920, height: 1080)
        #expect(resolution.convertTo(dimension: 720) == CMVideoDimensions(width: 1280, height: 720))
        #expect(resolution.convertTo(dimension: 480) == CMVideoDimensions(width: 854, height: 480))
        #expect(resolution.convertTo(dimension: 360) == CMVideoDimensions(width: 640, height: 360))
        #expect(resolution.convertTo(dimension: 160) == CMVideoDimensions(width: 284, height: 160))
    }

    @Test
    func portrait9x16() {
        let resolution = CMVideoDimensions(width: 1080, height: 1920)
        #expect(resolution.convertTo(dimension: 720) == CMVideoDimensions(width: 720, height: 1280))
        #expect(resolution.convertTo(dimension: 480) == CMVideoDimensions(width: 480, height: 854))
        #expect(resolution.convertTo(dimension: 360) == CMVideoDimensions(width: 360, height: 640))
        #expect(resolution.convertTo(dimension: 160) == CMVideoDimensions(width: 160, height: 284))
    }

    @Test
    func landscape4x3() {
        let resolution = CMVideoDimensions(width: 1920, height: 1440)
        #expect(resolution.convertTo(dimension: 1080) == CMVideoDimensions(width: 1440, height: 1080))
        #expect(resolution.convertTo(dimension: 720) == CMVideoDimensions(width: 960, height: 720))
        #expect(resolution.convertTo(dimension: 480) == CMVideoDimensions(width: 640, height: 480))
    }

    @Test
    func portrait4x3() {
        let resolution = CMVideoDimensions(width: 1440, height: 1920)
        #expect(resolution.convertTo(dimension: 1080) == CMVideoDimensions(width: 1080, height: 1440))
        #expect(resolution.convertTo(dimension: 720) == CMVideoDimensions(width: 720, height: 960))
    }
    
    @Test
    func isPortrait() {
        #expect(CMVideoDimensions(width: 1080, height: 1920).isPortrait() == true)
        #expect(CMVideoDimensions(width: 1920, height: 1080).isPortrait() == false)
        #expect(CMVideoDimensions(width: 1080, height: 1080).isPortrait() == false)
    }
    
    @Test
    func equality() {
        let a = CMVideoDimensions(width: 1920, height: 1080)
        let b = CMVideoDimensions(width: 1920, height: 1080)
        let c = CMVideoDimensions(width: 1280, height: 720)
        #expect(a == b)
        #expect(a != c)
    }
}


// MARK: - RTMP URL Parsing Tests

struct RtmpUrlSuite {
    @Test
    func twitchUrl() {
        let url = "rtmp://foo.com/app/live_asefwefwefwef"
        let streamUrl = makeRtmpUri(url: url)
        let streamKey = makeRtmpStreamKey(url: url)
        #expect(streamUrl == "rtmp://foo.com/app")
        #expect(streamKey == "live_asefwefwefwef")
    }

    @Test
    func kickUrl() {
        let url = "rtmp://foo.com/foobar"
        let streamUrl = makeRtmpUri(url: url)
        let streamKey = makeRtmpStreamKey(url: url)
        #expect(streamUrl == "rtmp://foo.com")
        #expect(streamKey == "foobar")
    }
}

// MARK: - Stream Stats Tests

struct StreamStatsSuite {
    @Test
    func streamStatsCreation() {
        let stats = StreamStats(
            rttMs: 50.0,
            packetsInFlight: 100.0,
            transportBitrate: 5_000_000,
            latency: 2000,
            mbpsSendRate: 5.0,
            relaxed: false
        )
        
        #expect(stats.rttMs == 50.0)
        #expect(stats.packetsInFlight == 100.0)
        #expect(stats.transportBitrate == 5_000_000)
        #expect(stats.latency == 2000)
        #expect(stats.mbpsSendRate == 5.0)
        #expect(stats.relaxed == false)
    }
    
    @Test
    func streamStatsWithNilValues() {
        let stats = StreamStats(
            rttMs: 50.0,
            packetsInFlight: 100.0,
            transportBitrate: nil,
            latency: nil,
            mbpsSendRate: nil,
            relaxed: nil
        )
        
        #expect(stats.transportBitrate == nil)
        #expect(stats.latency == nil)
        #expect(stats.mbpsSendRate == nil)
        #expect(stats.relaxed == nil)
    }
}

// MARK: - Adaptive Bitrate Settings Tests

struct AdaptiveBitrateSettingsSuite {
    @Test
    func defaultSettings() {
        let settings = adaptiveBitrateBelaboxSettings
        
        #expect(settings.packetsInFlight == 200)
        #expect(settings.minimumBitrate == 250_000)
    }
    
    @Test
    func customSettings() {
        let settings = AdaptiveBitrateSettings(
            packetsInFlight: 100,
            rttDiffHighFactor: 0.8,
            rttDiffHighAllowedSpike: 40,
            rttDiffHighMinDecrease: 200_000,
            pifDiffIncreaseFactor: 80_000,
            minimumBitrate: 500_000
        )
        
        #expect(settings.packetsInFlight == 100)
        #expect(settings.minimumBitrate == 500_000)
    }
}

// MARK: - Constants Tests

struct ConstantsSuite {
    @Test
    func adaptiveBitrateConstants() {
        #expect(adaptiveBitrateStart == 1_000_000)
        #expect(adaptiveBitrateTransportMinimum == adaptiveBitrateStart)
    }
}
