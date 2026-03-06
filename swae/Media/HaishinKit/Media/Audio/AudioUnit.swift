import AVFoundation
import Collections

var audioUnitRemoveWindNoise = false

struct AudioUnitAttachParams {
    let device: AVCaptureDevice?
    let builtinDelay: Double
    let bufferedAudio: UUID?
}

func makeChannelMap(
    numberOfInputChannels: Int,
    numberOfOutputChannels: Int,
    outputToInputChannelsMap: [Int: Int]
) -> [NSNumber] {
    var channelMap = Array(repeating: -1, count: numberOfOutputChannels)
    for inputIndex in 0..<min(numberOfInputChannels, numberOfOutputChannels) {
        channelMap[inputIndex] = inputIndex
    }
    for outputIndex in 0..<numberOfOutputChannels {
        if let inputIndex = outputToInputChannelsMap[outputIndex],
            inputIndex < numberOfInputChannels
        {
            channelMap[outputIndex] = inputIndex
        }
    }
    return channelMap.map { NSNumber(value: $0) }
}

final class AudioUnit: NSObject {
    let encoder = AudioEncoder(lockQueue: processorPipelineQueue)
    private var input: AVCaptureDeviceInput?
    private var output: AVCaptureAudioDataOutput?
    var muted = false
    weak var processor: Processor?
    private var selectedBufferedAudioId: UUID?
    private var bufferedAudios: [UUID: BufferedAudio] = [:]
    let session = AVCaptureSession()
    private var speechToTextEnabled = false
    private var bufferedBuiltinAudio: BufferedAudio?
    private var latestAudioStatusTime = 0.0
    private var stats = BufferedStats()

    // WebRTC collab: when set, mix this BufferedAudio source WITH the mic
    // (not replace). When nil (solo streaming), the if-let check is a single
    // pointer comparison — zero overhead. See Safety Analysis Mod 2.
    var mixingBufferedAudioId: UUID?

    /// Volume multiplier for remote guest audio (0.0 = silent, 1.0 = unity, 2.0 = boosted).
    /// Only accessed on processorPipelineQueue — no synchronization needed.
    var guestAudioVolume: Float = 1.0

    private var inputSourceFormat: AudioStreamBasicDescription? {
        didSet {
            guard inputSourceFormat != oldValue else {
                return
            }
            encoder.setInputSourceFormat(inputSourceFormat)
        }
    }

    func startRunning() {
        addSessionObservers()
        session.startRunning()
    }

    func stopRunning() {
        session.stopRunning()
        removeSessionObservers()
    }

    func attach(params: AudioUnitAttachParams) throws {
        processorPipelineQueue.async {
            self.selectedBufferedAudioId = params.bufferedAudio
            self.bufferedBuiltinAudio = BufferedAudio(
                cameraId: UUID(),
                name: "builtin",
                latency: params.builtinDelay,
                processor: self.processor,
                manualOutput: true
            )
        }
        if let device = params.device {
            try attachDevice(device)
        }
        // When device is nil: do NOT detach. Match moblin's behavior.
        // The existing capture session input/output remain intact.
        // selectedBufferedAudioId gates which audio source feeds the encoder.
    }

    /// Explicitly detach audio input/output from the capture session.
    /// Used by ContentView when navigating away from camera (not during mic switching).
    func detach() {
        detachDevice()
        processorPipelineQueue.async {
            self.selectedBufferedAudioId = nil
            self.bufferedBuiltinAudio = nil
        }
    }

    private func detachDevice() {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        if let input, session.inputs.contains(input) {
            session.removeInput(input)
            self.input = nil
            logger.info("audio-unit: Removed audio input from session")
        }
        if let output, session.outputs.contains(output) {
            session.removeOutput(output)
            self.output = nil
            logger.info("audio-unit: Removed audio output from session")
        }
    }

    func startEncoding(_ delegate: any AudioCodecDelegate) {
        encoder.delegate = delegate
        encoder.startRunning()
    }

    func stopEncoding() {
        encoder.stopRunning()
        encoder.delegate = nil
        processorPipelineQueue.async {
            self.inputSourceFormat = nil
        }
    }

    func setSpeechToText(enabled: Bool) {
        processorPipelineQueue.async {
            self.speechToTextEnabled = enabled
        }
    }

    private func attachDevice(_ device: AVCaptureDevice) throws {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        if let input, session.inputs.contains(input) {
            session.removeInput(input)
        }
        if let output, session.outputs.contains(output) {
            session.removeOutput(output)
        }
        input = try AVCaptureDeviceInput(device: device)
        if audioUnitRemoveWindNoise {
            if #available(iOS 18.0, *) {
                if input!.isWindNoiseRemovalSupported {
                    input!.multichannelAudioMode = .stereo
                    input!.isWindNoiseRemovalEnabled = true
                    logger.info(
                        "audio-unit: Wind noise removal enabled is \(input!.isWindNoiseRemovalEnabled)"
                    )
                } else {
                    logger.info("audio-unit: Wind noise removal is not supported on this device")
                }
            } else {
                logger.info("audio-unit: Wind noise removal needs iOS 18+")
            }
        }
        if session.canAddInput(input!) {
            session.addInput(input!)
        }
        output = AVCaptureAudioDataOutput()
        output?.setSampleBufferDelegate(self, queue: processorPipelineQueue)
        if session.canAddOutput(output!) {
            session.addOutput(output!)
        }
        session.automaticallyConfiguresApplicationAudioSession = false
    }

    func addBufferedAudio(cameraId: UUID, name: String, latency: Double) {
        processorPipelineQueue.async {
            self.addBufferedAudioInner(cameraId: cameraId, name: name, latency: latency)
        }
    }

    func removeBufferedAudio(cameraId: UUID) {
        processorPipelineQueue.async {
            self.removeBufferedAudioInner(cameraId: cameraId)
        }
    }

    func appendBufferedAudioSampleBuffer(cameraId: UUID, _ sampleBuffer: CMSampleBuffer) {
        processorPipelineQueue.async {
            self.appendBufferedAudioSampleBufferInner(cameraId: cameraId, sampleBuffer)
        }
    }

    func setBufferedAudioDrift(cameraId: UUID, drift: Double) {
        processorPipelineQueue.async {
            self.setBufferedAudioDriftInner(cameraId: cameraId, drift: drift)
        }
    }

    func setBufferedAudioTargetLatency(cameraId: UUID, latency: Double) {
        processorPipelineQueue.async {
            self.setBufferedAudioTargetLatencyInner(cameraId: cameraId, latency: latency)
        }
    }

    private func addBufferedAudioInner(cameraId: UUID, name: String, latency: Double) {
        let bufferedAudio = BufferedAudio(
            cameraId: cameraId,
            name: name,
            latency: latency,
            processor: processor,
            manualOutput: false
        )
        bufferedAudio.delegate = self
        bufferedAudios[cameraId] = bufferedAudio
    }

    private func removeBufferedAudioInner(cameraId: UUID) {
        bufferedAudios.removeValue(forKey: cameraId)?.stopOutput()
    }

    private func appendBufferedAudioSampleBufferInner(
        cameraId: UUID, _ sampleBuffer: CMSampleBuffer
    ) {
        bufferedAudios[cameraId]?.appendSampleBuffer(sampleBuffer)
    }

    private func setBufferedAudioDriftInner(cameraId: UUID, drift: Double) {
        bufferedAudios[cameraId]?.setDrift(drift: drift)
    }

    private func setBufferedAudioTargetLatencyInner(cameraId: UUID, latency: Double) {
        bufferedAudios[cameraId]?.setTargetLatency(latency: latency)
    }

    private func appendNewSampleBuffer(
        _ processor: Processor,
        _ sampleBuffer: CMSampleBuffer,
        _ presentationTimeStamp: CMTime
    ) {
        guard let sampleBuffer = sampleBuffer.muted(muted) else {
            return
        }
        if speechToTextEnabled {
            processor.delegate?.streamAudio(sampleBuffer: sampleBuffer)
        }
        inputSourceFormat = sampleBuffer.formatDescription?.audioStreamBasicDescription
        encoder.appendSampleBuffer(sampleBuffer, presentationTimeStamp)
        processor.recorder.appendAudio(sampleBuffer)
    }

    /// Mix remote audio PCM samples into the local mic buffer in-place.
    /// Uses CMBlockBuffer.getDataPointer() for direct memory access — zero allocation.
    /// The muted() function already uses this in-place pattern (CMBlockBufferFillDataBytes).
    /// Applies guestAudioVolume scaling to the remote samples before mixing.
    private func mixPCMInPlace(local: CMSampleBuffer, remote: CMSampleBuffer) {
        guard let (localPtr, localLength) = local.dataBuffer?.getDataPointer(),
              let (remotePtr, remoteLength) = remote.dataBuffer?.getDataPointer()
        else { return }

        let sampleSize = MemoryLayout<Int16>.size
        let count = min(localLength, remoteLength) / sampleSize
        guard count > 0 else { return }

        // Reinterpret Int8 pointers as Int16 for PCM sample access
        let localSamples = UnsafeMutableRawPointer(localPtr).bindMemory(to: Int16.self, capacity: count)
        let remoteSamples = UnsafeRawPointer(remotePtr).bindMemory(to: Int16.self, capacity: count)
        let volume = guestAudioVolume

        for i in 0..<count {
            let scaledRemote = Int32(Float(remoteSamples[i]) * volume)
            let sum = Int32(localSamples[i]) + scaledRemote
            localSamples[i] = Int16(clamping: sum)
        }
    }

    private func appendBufferedBuiltinAudio(
        _ sampleBuffer: CMSampleBuffer,
        _ presentationTimeStamp: CMTime
    ) -> BufferedAudio? {
        guard let bufferedBuiltinAudio,
            bufferedBuiltinAudio.latency > 0,
            let sampleBuffer = sampleBuffer.deepCopyAudioSampleBuffer()
        else {
            return nil
        }
        let presentationTimeStamp =
            presentationTimeStamp + CMTime(seconds: bufferedBuiltinAudio.latency)
        guard let sampleBuffer = sampleBuffer.replacePresentationTimeStamp(presentationTimeStamp)
        else {
            return nil
        }
        bufferedBuiltinAudio.appendSampleBuffer(sampleBuffer)
        return bufferedBuiltinAudio
    }

    private func shouldUpdateAudioLevel(_ sampleBuffer: CMSampleBuffer) -> Bool {
        let now = sampleBuffer.presentationTimeStamp.seconds
        if now - latestAudioStatusTime > 0.2 {
            latestAudioStatusTime = now
            return true
        } else {
            return false
        }
    }

    // MARK: - AVCaptureSession Observers (matching VideoUnit pattern)

    private func addSessionObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSessionRuntimeError),
            name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(
            self, selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    private func removeSessionObservers() {
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    @objc private func handleSessionRuntimeError(_ notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        logger.error("audio-unit: Session runtime error: \(error.localizedDescription)")
        // Use processorControlQueue (not main) — startRunning() is a blocking call
        // that can take 30ms+. Matches VideoUnit's pattern.
        processorControlQueue.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
            guard let self, self.input != nil, !self.session.isRunning else { return }
            logger.info("audio-unit: Attempting session restart after runtime error")
            self.session.startRunning()
        }
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        logger.info("audio-unit: Session was interrupted")
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        logger.info("audio-unit: Session interruption ended")
        // Use processorControlQueue (not main) — startRunning() is a blocking call.
        // Matches VideoUnit's sessionInterruptionEnded pattern.
        processorControlQueue.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }
}

extension AudioUnit: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let processor else {
            return
        }
        // Workaround for audio drift on iPhone 15 Pro Max running iOS 17. Probably issue on more models.
        let presentationTimeStamp = syncTimeToVideo(
            processor: processor, sampleBuffer: sampleBuffer)
        var sampleBuffer = sampleBuffer
        if let bufferedAudio = appendBufferedBuiltinAudio(sampleBuffer, presentationTimeStamp) {
            sampleBuffer =
                bufferedAudio.getSampleBuffer(presentationTimeStamp.seconds) ?? sampleBuffer
        }
        guard selectedBufferedAudioId == nil else {
            return
        }
        // WebRTC collab: mix remote guest audio into the mic buffer before encoding.
        // This runs AFTER the selectedBufferedAudioId guard (GoPro mode returns early above).
        // When mixingBufferedAudioId is nil (solo streaming), this is a single nil-check.
        if let mixingId = mixingBufferedAudioId,
           let remoteAudio = bufferedAudios[mixingId],
           let remoteSample = remoteAudio.getSampleBuffer(presentationTimeStamp.seconds)
        {
            mixPCMInPlace(local: sampleBuffer, remote: remoteSample)
        }
        if shouldUpdateAudioLevel(sampleBuffer) {
            var audioLevel: Float
            if muted {
                audioLevel = .nan
            } else if let channel = connection.audioChannels.first {
                audioLevel = channel.averagePowerLevel
            } else {
                audioLevel = 0.0
            }
            let sampleRate =
                sampleBuffer.formatDescription?.audioStreamBasicDescription?.mSampleRate ?? 0
            processor.delegate?.stream(
                audioLevel: audioLevel,
                numberOfAudioChannels: connection.audioChannels.count,
                sampleRate: sampleRate)
        }
        appendNewSampleBuffer(processor, sampleBuffer, presentationTimeStamp)
    }
}

extension AudioUnit: BufferedAudioSampleBufferDelegate {
    func didOutputBufferedSampleBuffer(cameraId: UUID, sampleBuffer: CMSampleBuffer) {
        guard selectedBufferedAudioId == cameraId, let processor else {
            return
        }
        if shouldUpdateAudioLevel(sampleBuffer) {
            let numberOfAudioChannels = Int(
                sampleBuffer.formatDescription?.numberOfAudioChannels() ?? 0)
            let sampleRate =
                sampleBuffer.formatDescription?.audioStreamBasicDescription?.mSampleRate ?? 0
            processor.delegate?.stream(
                audioLevel: .infinity,
                numberOfAudioChannels: numberOfAudioChannels,
                sampleRate: sampleRate)
        }
        appendNewSampleBuffer(processor, sampleBuffer, sampleBuffer.presentationTimeStamp)
    }
}

private func syncTimeToVideo(processor: Processor, sampleBuffer: CMSampleBuffer) -> CMTime {
    var presentationTimeStamp = sampleBuffer.presentationTimeStamp
    if let audioClock = processor.audio.session.synchronizationClock,
        let videoClock = processor.video.session.synchronizationClock
    {
        let audioTimescale = sampleBuffer.presentationTimeStamp.timescale
        let seconds = audioClock.convertTime(presentationTimeStamp, to: videoClock).seconds
        let value = CMTimeValue(seconds * Double(audioTimescale))
        presentationTimeStamp = CMTime(value: value, timescale: audioTimescale)
    }
    return presentationTimeStamp
}
