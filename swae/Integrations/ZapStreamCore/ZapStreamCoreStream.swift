import AVFoundation
import Combine
import Foundation

// MARK: - Zap Stream Core Stream Protocol

protocol ZapStreamCoreStreamDelegate: AnyObject {
    func zapStreamCoreOnError(error: Error)
}

// MARK: - Zap Stream Core Stream Implementation
//
// This class manages the zap-stream-core API interactions (metadata, stop).
// Actual RTMP/SRT streaming is handled by Media's RtmpStream via Model.startNetStream().

class ZapStreamCoreStream: ObservableObject {
    private let apiClient: ZapStreamCoreApiClient
    private weak var delegate: ZapStreamCoreStreamDelegate?
    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    @Published var isConnected = false
    @Published var currentStreamId: String?
    @Published var streamUrl: String?
    @Published var streamKey: String?
    @Published var error: String?

    init(
        apiClient: ZapStreamCoreApiClient, processor: Processor,
        delegate: ZapStreamCoreStreamDelegate
    ) {
        self.apiClient = apiClient
        self.delegate = delegate

        setupBindings()
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func setPreferredProtocol(_ protocol: ZapStreamCoreProtocol) {
        // Stored for future use; actual protocol is determined by Media via stream.getProtocol()
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

    func stopStreaming() {
        guard let streamId = currentStreamId else { return }
        guard let appState = appState else {
            handleError(ZapStreamCoreError.authenticationFailed)
            return
        }

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
                            self?.currentStreamId = nil
                            self?.streamUrl = nil
                            self?.streamKey = nil
                        }
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.error = error.localizedDescription
            self.delegate?.zapStreamCoreOnError(error: error)
        }
    }

    func getStreamingUrl() -> String? {
        guard let streamUrl = streamUrl, let streamKey = streamKey else { return nil }
        return "\(streamUrl)/\(streamKey)"
    }
}
