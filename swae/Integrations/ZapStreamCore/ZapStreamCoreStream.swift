import AVFoundation
import Combine
import Foundation

// MARK: - Zap Stream Core Stream Protocol

protocol ZapStreamCoreStreamDelegate: AnyObject {
    func zapStreamCoreOnConnected()
    func zapStreamCoreOnDisconnected(reason: String)
    func zapStreamCoreOnError(error: Error)
    func zapStreamCoreOnStreamStarted(streamId: String)
    func zapStreamCoreOnStreamStopped(streamId: String)
}

// MARK: - Zap Stream Core Stream Implementation

class ZapStreamCoreStream: ObservableObject {
    private let apiClient: ZapStreamCoreApiClient
    private let processor: Processor
    private weak var delegate: ZapStreamCoreStreamDelegate?
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    @Published var isConnected = false
    @Published var isStreaming = false
    @Published var currentStreamId: String?
    @Published var streamUrl: String?
    @Published var streamKey: String?
    @Published var error: String?

    private var rtmpStream: RtmpStream?
    private var srtStream: SrtStreamNew?
    private var preferredProtocol: ZapStreamCoreProtocol = .rtmp

    init(
        apiClient: ZapStreamCoreApiClient, processor: Processor,
        delegate: ZapStreamCoreStreamDelegate
    ) {
        self.apiClient = apiClient
        self.processor = processor
        self.delegate = delegate

        setupBindings()
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    private func setupBindings() {
        apiClient.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)

        apiClient.$currentStream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stream in
                self?.currentStreamId = stream?.id
                self?.streamUrl = stream?.rtmpUrl
                self?.streamKey = stream?.streamKey
            }
            .store(in: &cancellables)

        apiClient.$error
            .receive(on: DispatchQueue.main)
            .assign(to: \.error, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Stream Management

    func createAndStartStream(title: String, description: String? = nil, isPublic: Bool = true) {
        // For Zap Stream Core, we don't need to create a stream via API
        // We just stream directly to the RTMP URL that was configured in the wizard
        // The stream URL should already be set in the stream configuration

        // Create a mock stream info with the configured URL
        let streamInfo = ZapStreamCoreStreamInfo(
            id: UUID().uuidString,
            title: title,
            description: description ?? "",
            streamKey: "",  // Not needed since URL already contains the key
            rtmpUrl: "",  // Will be set from stream configuration
            srtUrl: nil,
            isLive: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        startStreaming(stream: streamInfo)
    }

    func startStreaming(stream: ZapStreamCoreStreamInfo) {
        guard !isStreaming else { return }

        // For Zap Stream Core, we don't need to call the API to start streaming
        // We just stream directly to the RTMP URL that was configured in the wizard
        // The stream URL should already be set in the stream configuration

        currentStreamId = stream.id

        // The stream URL and key should be passed from the Model's stream configuration
        // For now, we'll start local streaming and let the Model handle the URL

        startLocalStreaming()
    }

    private func startLocalStreaming() {
        // For Zap Stream Core, we need to get the stream URL from the current stream configuration
        // The URL should already be the full RTMP URL with stream key from the wizard

        // We'll need to get this from the Model's current stream configuration
        // For now, let's assume the URL is passed correctly from the Model

        guard let currentStreamUrl = getCurrentStreamUrl() else {
            handleError(ZapStreamCoreError.invalidConfiguration)
            return
        }

        switch preferredProtocol {
        case .rtmp:
            startRtmpStreaming(url: currentStreamUrl)
        case .srt:
            startSrtStreaming(url: currentStreamUrl)
        }
    }

    private func getCurrentStreamUrl() -> String? {
        // This should get the stream URL from the Model's current stream configuration
        // For now, we'll return nil and let the Model handle this
        return nil
    }

    private func startRtmpStreaming(url: String) {
        rtmpStream = RtmpStream(name: "ZapStreamCore", processor: processor, delegate: self)
        rtmpStream?.setUrl(url)
        rtmpStream?.connect()

        DispatchQueue.main.async {
            self.isStreaming = true
            self.delegate?.zapStreamCoreOnStreamStarted(streamId: self.currentStreamId ?? "")
        }
    }

    private func startSrtStreaming(url: String) {
        // Parse SRT URL to extract stream ID
        guard let urlComponents = URLComponents(string: url),
            let host = urlComponents.host,
            let port = urlComponents.port
        else {
            handleError(ZapStreamCoreError.invalidConfiguration)
            return
        }

        // Extract stream ID from path or query parameters
        let streamId = urlComponents.path.replacingOccurrences(of: "/", with: "")

        srtStream = SrtStreamNew(processor: processor, timecodesEnabled: false, delegate: self)
        srtStream?.open(streamId: streamId, latency: 1000)  // 1 second latency

        DispatchQueue.main.async {
            self.isStreaming = true
            self.delegate?.zapStreamCoreOnStreamStarted(streamId: self.currentStreamId ?? "")
        }
    }

    func stopStreaming() {
        guard isStreaming, let streamId = currentStreamId else { return }
        guard let appState = appState else {
            handleError(ZapStreamCoreError.authenticationFailed)
            return
        }

        // Stop local streaming first
        stopLocalStreaming()

        // Stop stream via API
        apiClient.stopStream(appState: appState, streamId: streamId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.handleError(error)
                    }
                },
                receiveValue: { [weak self] success in
                    if success {
                        DispatchQueue.main.async {
                            self?.isStreaming = false
                            self?.currentStreamId = nil
                            self?.streamUrl = nil
                            self?.streamKey = nil
                            self?.delegate?.zapStreamCoreOnStreamStopped(streamId: streamId)
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func stopLocalStreaming() {
        rtmpStream?.disconnect()
        rtmpStream = nil

        srtStream?.close()
        srtStream = nil

        DispatchQueue.main.async {
            self.isStreaming = false
        }
    }

    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.error = error.localizedDescription
            self.delegate?.zapStreamCoreOnError(error: error)
        }
    }

    func setPreferredProtocol(_ protocol: ZapStreamCoreProtocol) {
        preferredProtocol = `protocol`
    }

    func getStreamingUrl() -> String? {
        guard let streamUrl = streamUrl, let streamKey = streamKey else { return nil }
        return "\(streamUrl)/\(streamKey)"
    }
}

// MARK: - Zap Stream Core Protocol Enum
// Note: ZapStreamCoreProtocol is defined in Settings.swift

// MARK: - RTMP Stream Delegate

extension ZapStreamCoreStream: RtmpStreamDelegate {
    func rtmpStreamStatus(_ rtmpStream: RtmpStream, code: String) {
        switch code {
        case RtmpConnectionCode.connectClosed.rawValue:
            DispatchQueue.main.async {
                self.isConnected = false
                self.delegate?.zapStreamCoreOnDisconnected(reason: "RTMP connection closed")
            }
        case RtmpConnectionCode.connectFailed.rawValue:
            DispatchQueue.main.async {
                self.isConnected = false
                self.delegate?.zapStreamCoreOnDisconnected(reason: "RTMP connection failed")
            }
        case RtmpConnectionCode.connectRejected.rawValue:
            DispatchQueue.main.async {
                self.isConnected = false
                self.delegate?.zapStreamCoreOnDisconnected(reason: "RTMP connection rejected")
            }
        default:
            break
        }
    }

    func rtmpStreamConnected(_ rtmpStream: RtmpStream) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.delegate?.zapStreamCoreOnConnected()
        }
    }
}

// MARK: - SRT Stream Delegate

extension ZapStreamCoreStream: SrtStreamNewDelegate {
    func srtStreamConnected() {
        DispatchQueue.main.async {
            self.isConnected = true
            self.delegate?.zapStreamCoreOnConnected()
        }
    }

    func srtStreamDisconnected() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.delegate?.zapStreamCoreOnDisconnected(reason: "SRT connection disconnected")
        }
    }

    func srtStreamOutput(packet: Data) {
        // Handle SRT output packets if needed
    }
}
