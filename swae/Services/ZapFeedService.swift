//
//  ZapFeedService.swift
//  swae
//
//  Created by Suhail Saqan on 3/8/25.
//

import AVFoundation
import Combine
import Foundation
import NostrSDK
import SwiftUI
import UIKit

/// Service that manages the zap feed - collecting and organizing zap events from relays
class ZapFeedService: ObservableObject {
    @Published var zapFeed: [NostrEvent] = []
    @Published var isLoading = false
    @Published var error: String?

    private var cancellables = Set<AnyCancellable>()
    private var isListening = false

    // Cache for processed events to avoid duplicates
    private var processedEventIds = Set<String>()

    func startListening(appState: AppState) {
        guard !isListening else { return }

        isListening = true
        isLoading = true

        // Subscribe to zap events
        subscribeToZapEvents(appState: appState)

        // Load existing zap events
        loadExistingZapEvents(appState: appState)
    }

    func stopListening() {
        isListening = false
        cancellables.removeAll()
    }

    private func subscribeToZapEvents(appState: AppState) {
        // Listen for changes in zap collections
        appState.$zapRequests
            .sink { [weak self] newRequests in
                self?.processNewZapRequests(newRequests)
            }
            .store(in: &cancellables)

        appState.$zapReceipts
            .sink { [weak self] newReceipts in
                self?.processNewZapReceipts(newReceipts)
            }
            .store(in: &cancellables)
    }

    private func loadExistingZapEvents(appState: AppState) {
        // Get existing zap events from app state
        let existingZapRequests = appState.zapRequests
        let existingZapReceipts = appState.zapReceipts

        // Combine and sort by timestamp
        let allZaps = (existingZapRequests + existingZapReceipts).sorted {
            $0.createdAt > $1.createdAt
        }

        DispatchQueue.main.async {
            self.zapFeed = allZaps
            self.isLoading = false
        }
    }

    private func processNewZapRequests(_ newRequests: [LightningZapRequestEvent]) {
        let newEvents = newRequests.filter { !processedEventIds.contains($0.id) }
        guard !newEvents.isEmpty else { return }

        processedEventIds.formUnion(newEvents.map { $0.id })

        DispatchQueue.main.async {
            let newFeed = (newEvents + self.zapFeed)
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(1000)  // Limit to 1000 most recent events

            self.zapFeed = Array(newFeed)
        }
    }

    private func processNewZapReceipts(_ newReceipts: [LightningZapsReceiptEvent]) {
        let newEvents = newReceipts.filter { !processedEventIds.contains($0.id) }
        guard !newEvents.isEmpty else { return }

        processedEventIds.formUnion(newEvents.map { $0.id })

        DispatchQueue.main.async {
            let newFeed = (newEvents + self.zapFeed)
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(1000)  // Limit to 1000 most recent events

            self.zapFeed = Array(newFeed)
        }
    }

    func refreshFeed(appState: AppState) {
        isLoading = true
        processedEventIds.removeAll()

        // Re-subscribe to get fresh data
        subscribeToZapEvents(appState: appState)

        // Load existing events again
        loadExistingZapEvents(appState: appState)
    }

    func getZapStats() -> ZapStats {
        let sentZaps = zapFeed.filter { $0 is LightningZapsReceiptEvent }
        let receivedZaps = zapFeed.filter { $0 is LightningZapRequestEvent }

        let totalSentAmount = sentZaps.reduce(0) {
            $0 + Int64(($1 as? LightningZapsReceiptEvent)?.description?.amount ?? 0)
        }
        let totalReceivedAmount = receivedZaps.reduce(0) {
            $0 + Int64(($1 as? LightningZapRequestEvent)?.amount ?? 0)
        }

        return ZapStats(
            totalSent: sentZaps.count,
            totalReceived: receivedZaps.count,
            totalSentAmount: totalSentAmount,
            totalReceivedAmount: totalReceivedAmount
        )
    }
}

struct ZapStats {
    let totalSent: Int
    let totalReceived: Int
    let totalSentAmount: Int64
    let totalReceivedAmount: Int64

    var netAmount: Int64 {
        totalReceivedAmount - totalSentAmount
    }

    var totalActivity: Int {
        totalSent + totalReceived
    }
}

// MARK: - QR Code Scanner Support

struct QRCodeScannerView: UIViewControllerRepresentable {
    let completion: (String) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let controller = QRCodeScannerViewController()
        controller.completion = completion
        return controller
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {
    }
}

class QRCodeScannerViewController: UIViewController {
    var completion: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startCaptureSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCaptureSession()
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()

        guard let captureSession = captureSession else { return }

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }
    }

    private func setupUI() {
        view.backgroundColor = UIColor.black

        guard let captureSession = captureSession else { return }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)

        // Add close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Cancel", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeButton.layer.cornerRadius = 8
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)

        view.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 80),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        // Add scanning frame
        let scanningFrame = UIView()
        scanningFrame.backgroundColor = UIColor.clear
        scanningFrame.layer.borderColor = UIColor.white.cgColor
        scanningFrame.layer.borderWidth = 2
        scanningFrame.layer.cornerRadius = 12

        view.addSubview(scanningFrame)
        scanningFrame.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scanningFrame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanningFrame.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            scanningFrame.widthAnchor.constraint(equalToConstant: 250),
            scanningFrame.heightAnchor.constraint(equalToConstant: 250),
        ])

        // Add instruction label
        let instructionLabel = UILabel()
        instructionLabel.text = "Scan QR code to get pubkey"
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        view.addSubview(instructionLabel)
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(
                equalTo: scanningFrame.bottomAnchor, constant: 20),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    private func startCaptureSession() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func stopCaptureSession() {
        captureSession?.stopRunning()
    }

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
}

extension QRCodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else {
                return
            }
            guard let stringValue = readableObject.stringValue else { return }

            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            completion?(stringValue)
            dismiss(animated: true)
        }
    }
}
