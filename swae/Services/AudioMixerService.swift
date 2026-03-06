//
//  AudioMixerService.swift
//  swae
//
//  Bridges WebRTC remote audio into the RTMP broadcast by tapping
//  AVAudioEngine's output (which includes WebRTC's decoded remote audio)
//  and feeding it into AudioUnit's BufferedAudio pipeline for mixing
//  with the local mic.
//
//  The WebRTC iOS SDK plays remote audio through Core Audio's Voice
//  Processing I/O (VPIO) AudioUnit. We tap AVAudioEngine's output node
//  to capture what VPIO renders to the speaker.
//
//  IMPORTANT: The format parameter for installTap MUST be nil.
//  A standalone AVAudioEngine with no connections has an invalid output
//  format (0 channels) when AVCaptureSession + WebRTC VPIO already own
//  the hardware. Passing nil lets the system pick the native format,
//  and we read the actual format from the buffer in the callback.
//
//  DIAGNOSTIC: If the tap captures silence, the logs will show
//  "audio-mixer: ⚠️ Silent buffer" and we need to switch to the
//  RTCAudioDevice injection approach.
//

import AVFoundation
import Foundation

final class AudioMixerService {
    private let audioUnit: AudioUnit
    private let sourceId: UUID
    private var engine: AVAudioEngine?
    private var isCapturing = false
    private var silentBufferCount = 0
    private var nonSilentBufferCount = 0
    private var capturedFormat: AVAudioFormat?

    init(audioUnit: AudioUnit) {
        self.audioUnit = audioUnit
        self.sourceId = UUID()
    }

    deinit {
        stopCapturing()
    }

    /// Start capturing WebRTC remote audio via AVAudioEngine output tap.
    /// Call this after the WebRTC call connects and remote audio is flowing.
    func startCapturing() {
        guard !isCapturing else { return }

        // Register a BufferedAudio source for the remote audio
        audioUnit.addBufferedAudio(
            cameraId: sourceId,
            name: "webrtc-guest",
            latency: 0.1  // 100ms buffer for jitter absorption
        )

        // Enable mixing mode in AudioUnit
        processorPipelineQueue.async {
            self.audioUnit.mixingBufferedAudioId = self.sourceId
        }

        // Set up AVAudioEngine to tap the output
        let engine = AVAudioEngine()
        self.engine = engine

        let output = engine.outputNode

        // MUST pass nil for format — a standalone AVAudioEngine has no valid
        // output format when AVCaptureSession + WebRTC VPIO own the hardware.
        // Passing the node's outputFormat causes SetOutputFormat to throw
        // (0 channels / invalid format). nil lets the system pick automatically.
        output.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
            guard let self else { return }

            // Capture the actual format from the first buffer
            if self.capturedFormat == nil {
                self.capturedFormat = buffer.format
                logger.info("audio-mixer: Captured format: \(buffer.format)")
            }

            // Diagnostic: check if buffer contains actual audio
            self.logBufferDiagnostics(buffer)

            if let sampleBuffer = self.convertToCMSampleBuffer(buffer, time) {
                self.audioUnit.appendBufferedAudioSampleBuffer(
                    cameraId: self.sourceId,
                    sampleBuffer
                )
            }
        }

        do {
            try engine.start()
            isCapturing = true
            logger.info("audio-mixer: Started capturing remote audio via AVAudioEngine tap")
        } catch {
            logger.error("audio-mixer: Failed to start AVAudioEngine: \(error.localizedDescription)")
            cleanup()
        }
    }

    /// Stop capturing and clean up.
    func stopCapturing() {
        guard isCapturing else { return }

        engine?.outputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        capturedFormat = nil

        // Disable mixing mode
        processorPipelineQueue.async {
            self.audioUnit.mixingBufferedAudioId = nil
        }

        // Remove the BufferedAudio source
        audioUnit.removeBufferedAudio(cameraId: sourceId)

        isCapturing = false
        logger.info("audio-mixer: Stopped capturing remote audio (silent=\(silentBufferCount), nonSilent=\(nonSilentBufferCount))")
    }

    private func cleanup() {
        engine?.outputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        capturedFormat = nil
        audioUnit.removeBufferedAudio(cameraId: sourceId)
        processorPipelineQueue.async {
            self.audioUnit.mixingBufferedAudioId = nil
        }
    }

    // MARK: - Diagnostics

    private func logBufferDiagnostics(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Calculate RMS of first channel to detect silence
        var rms: Float = 0
        if let floatData = buffer.floatChannelData {
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = floatData[0][i]
                sum += sample * sample
            }
            rms = sqrtf(sum / Float(frameLength))
        } else if let int16Data = buffer.int16ChannelData {
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = Float(int16Data[0][i]) / Float(Int16.max)
                sum += sample * sample
            }
            rms = sqrtf(sum / Float(frameLength))
        }

        let isSilent = rms < 0.0001
        if isSilent {
            silentBufferCount += 1
        } else {
            nonSilentBufferCount += 1
        }

        // Log first 10 buffers and then every 500th
        let total = silentBufferCount + nonSilentBufferCount
        if total <= 10 || total % 500 == 0 {
            if isSilent {
                logger.info("audio-mixer: ⚠️ Silent buffer #\(total) (rms=\(rms))")
            } else {
                logger.info("audio-mixer: ✅ Audio buffer #\(total) (rms=\(String(format: "%.4f", rms)))")
            }
        }
    }

    // MARK: - AVAudioPCMBuffer → CMSampleBuffer Conversion

    private func convertToCMSampleBuffer(
        _ buffer: AVAudioPCMBuffer,
        _ time: AVAudioTime
    ) -> CMSampleBuffer? {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let format = buffer.format

        // Get the PCM data — prefer Int16 for compatibility with AudioUnit's encoder
        if let int16Data = buffer.int16ChannelData {
            let dataSize = frameLength * MemoryLayout<Int16>.size
            let dataPointer = UnsafeRawPointer(int16Data[0])
            return createSampleBuffer(
                from: dataPointer,
                dataSize: dataSize,
                frameLength: frameLength,
                time: time,
                format: format
            )
        } else if let floatData = buffer.floatChannelData {
            // Convert Float32 → Int16
            let int16Buffer = UnsafeMutableBufferPointer<Int16>.allocate(capacity: frameLength)
            for i in 0..<frameLength {
                let clamped = max(-1.0, min(1.0, floatData[0][i]))
                int16Buffer[i] = Int16(clamped * Float(Int16.max))
            }
            let dataSize = frameLength * MemoryLayout<Int16>.size
            defer { int16Buffer.deallocate() }
            return createSampleBuffer(
                from: UnsafeRawPointer(int16Buffer.baseAddress!),
                dataSize: dataSize,
                frameLength: frameLength,
                time: time,
                format: format
            )
        } else {
            return nil
        }
    }

    private func createSampleBuffer(
        from dataPointer: UnsafeRawPointer,
        dataSize: Int,
        frameLength: Int,
        time: AVAudioTime,
        format: AVAudioFormat
    ) -> CMSampleBuffer? {
        // Create CMBlockBuffer with a copy of the audio data
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        status = CMBlockBufferReplaceDataBytes(
            with: dataPointer,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )
        guard status == kCMBlockBufferNoErr else { return nil }

        // Create audio format description for Int16 PCM mono
        var asbd = AudioStreamBasicDescription(
            mSampleRate: format.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Int16>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Int16>.size),
            mChannelsPerFrame: 1,  // Mono
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else { return nil }

        // Calculate presentation timestamp
        let sampleRate = format.sampleRate
        let pts = CMTime(
            value: CMTimeValue(time.sampleTime),
            timescale: CMTimeScale(sampleRate)
        )

        // Create CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(frameLength),
            presentationTimeStamp: pts,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr else { return nil }

        return sampleBuffer
    }
}
