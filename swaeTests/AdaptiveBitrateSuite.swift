import AVFoundation
import Collections
@testable import swae
import Testing

private class Handler {
    var bitrates: Deque<UInt32> = []
}

extension Handler: AdaptiveBitrateDelegate {
    func adaptiveBitrateSetVideoStreamBitrate(bitrate: UInt32) {
        bitrates.append(bitrate)
    }
}

private func makeStats(bitrate: Int64) -> StreamStats {
    return StreamStats(rttMs: 30,
                       packetsInFlight: 15,
                       transportBitrate: bitrate,
                       latency: 3000,
                       mbpsSendRate: Double(bitrate),
                       relaxed: false)
}

private func update(belabox: AdaptiveBitrateSrtBela, bitrate: Int64) async throws {
    try await sleep(milliSeconds: 20)
    belabox.update(stats: makeStats(bitrate: bitrate))
}

struct AdaptiveBitrateSuite {
    // Note: Swae's AdaptiveBitrateSrtBela initializes curBitrate lazily (to 0),
    // while Moblin initializes it to adaptiveBitrateStart in the constructor.
    // These tests are adjusted to match Swae's behavior.
    
    @Test
    func belaboxInitialState() async throws {
        let handler = Handler()
        let belabox = AdaptiveBitrateSrtBela(targetBitrate: 5_000_000, delegate: handler)
        belabox.setSettings(settings: adaptiveBitrateBelaboxSettings)
        
        // Swae initializes curBitrate to 0, then sets it to adaptiveBitrateStart on first update
        #expect(belabox.getCurrentBitrate() == 0)
        #expect(handler.bitrates.isEmpty)
        
        // After first update, bitrate should be set
        try await update(belabox: belabox, bitrate: 5_000_000)
        #expect(belabox.getCurrentBitrate() > 0)
    }
    
    @Test
    func belaboxSettingsApplied() async throws {
        let handler = Handler()
        let belabox = AdaptiveBitrateSrtBela(targetBitrate: 5_000_000, delegate: handler)
        
        // Verify settings can be applied without crash
        belabox.setSettings(settings: adaptiveBitrateBelaboxSettings)
        belabox.setTargetBitrate(bitrate: 3_000_000)
        
        // Run a few updates to verify stability
        for _ in 0..<5 {
            try await update(belabox: belabox, bitrate: 3_000_000)
        }
        
        // Should have received some bitrate updates
        #expect(!handler.bitrates.isEmpty)
    }
}
