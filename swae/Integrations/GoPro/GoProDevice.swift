import CoreBluetooth
import Foundation

// GoPro BLE UUIDs
// GP-XXXX = b5f9XXXX-aa8d-11e3-9046-0002a5d5c51b
private func gpUUID(_ short: String) -> CBUUID {
    CBUUID(string: "b5f9\(short)-aa8d-11e3-9046-0002a5d5c51b")
}

private let goProServiceUUID = CBUUID(string: "FEA6")
private let networkMgmtServiceUUID = gpUUID("0090")

// Characteristics
private let commandUUID = gpUUID("0072")
private let commandResponseUUID = gpUUID("0073")
private let queryUUID = gpUUID("0076")
private let queryResponseUUID = gpUUID("0077")
private let networkMgmtCommandUUID = gpUUID("0091")
private let networkMgmtResponseUUID = gpUUID("0092")

// Feature/Action IDs
// From https://gopro.github.io/OpenGoPro/ble/protocol/id_tables.html#protobuf-ids
private let networkMgmtFeatureId: UInt8 = 0x02
private let startScanActionId: UInt8 = 0x02     // RequestStartScan
private let getApEntriesActionId: UInt8 = 0x03  // RequestGetApEntries
private let connectActionId: UInt8 = 0x04       // RequestConnect (known network)
private let connectNewActionId: UInt8 = 0x05    // RequestConnectNew (new network)
private let livestreamFeatureId: UInt8 = 0xF1
private let setLiveStreamModeActionId: UInt8 = 0x79
private let getLiveStreamStatusFeatureId: UInt8 = 0xF5
private let getLiveStreamStatusActionId: UInt8 = 0x74

enum GoProDeviceState: String {
    case idle
    case discovering
    case connecting
    case discoveringServices
    case subscribing
    case scanning
    case connectingToWifi
    case wifiSetupFailed
    case configuringStream
    case pollingStatus
    case startingStream
    case streaming
    case stoppingStream
}

protocol GoProDeviceDelegate: AnyObject {
    func goProDeviceStreamingState(_ device: GoProDevice, state: GoProDeviceState)
}

class GoProDevice: NSObject {
    private var wifiSsid: String?
    private var wifiPassword: String?
    private var rtmpUrl: String?
    private var resolution: GoProWindowSize = .r1080p
    private var minimumBitrate: Int32 = 4000
    private var maximumBitrate: Int32 = 8000
    private var startingBitrate: Int32 = 6000
    private var deviceId: UUID?
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var state: GoProDeviceState = .idle
    weak var delegate: (any GoProDeviceDelegate)?
    private let startStreamingTimer = SimpleTimer(queue: .main)
    private let stopStreamingTimer = SimpleTimer(queue: .main)

    // Characteristics
    private var commandChar: CBCharacteristic?
    private var commandResponseChar: CBCharacteristic?
    private var queryChar: CBCharacteristic?
    private var queryResponseChar: CBCharacteristic?
    private var networkMgmtCommandChar: CBCharacteristic?
    private var networkMgmtResponseChar: CBCharacteristic?

    // Response reassembly
    private var pendingResponsePackets: [CBUUID: [Data]] = [:]
    private var subscribedCount = 0
    private var expectedSubscriptions = 0
    private var isFirstWifiConnect = true
    private var wifiRetryCount = 0
    private let maxWifiRetries = 3
    private let wifiRetryTimer = SimpleTimer(queue: .main)
    private var currentScanId: Int32 = 0
    private var scanEntries: [GoProScanEntry] = []

    func startLiveStream(
        wifiSsid: String,
        wifiPassword: String,
        rtmpUrl: String,
        resolution: GoProWindowSize,
        minimumBitrate: Int32,
        maximumBitrate: Int32,
        startingBitrate: Int32,
        deviceId: UUID
    ) {
        logger.debug("gopro-device: Start live stream")
        self.wifiSsid = wifiSsid
        self.wifiPassword = wifiPassword
        self.rtmpUrl = rtmpUrl
        self.resolution = resolution
        self.minimumBitrate = minimumBitrate
        self.maximumBitrate = maximumBitrate
        self.startingBitrate = startingBitrate
        self.deviceId = deviceId
        reset()
        startStartStreamingTimer()
        setState(state: .discovering)
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func stopLiveStream() {
        guard state != .idle else { return }
        logger.debug("gopro-device: Stop live stream")
        stopStartStreamingTimer()
        startStopStreamingTimer()
        sendShutterOff()
        setState(state: .stoppingStream)
    }

    func getState() -> GoProDeviceState {
        return state
    }

    private func reset() {
        stopStartStreamingTimer()
        stopStopStreamingTimer()
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralManager = nil
        peripheral = nil
        commandChar = nil
        commandResponseChar = nil
        queryChar = nil
        queryResponseChar = nil
        networkMgmtCommandChar = nil
        networkMgmtResponseChar = nil
        pendingResponsePackets = [:]
        subscribedCount = 0
        expectedSubscriptions = 0
        wifiRetryCount = 0
        wifiRetryTimer.stop()
        setState(state: .idle)
    }

    private func setState(state: GoProDeviceState) {
        guard state != self.state else { return }
        logger.debug("gopro-device: State \(self.state.rawValue) → \(state.rawValue)")
        self.state = state
        delegate?.goProDeviceStreamingState(self, state: state)
    }

    // MARK: - Timers

    private func startStartStreamingTimer() {
        startStreamingTimer.startSingleShot(timeout: 60) { [weak self] in
            logger.info("gopro-device: Start streaming timeout")
            self?.reset()
        }
    }

    private func stopStartStreamingTimer() {
        startStreamingTimer.stop()
    }

    private func startStopStreamingTimer() {
        stopStreamingTimer.startSingleShot(timeout: 10) { [weak self] in
            logger.info("gopro-device: Stop streaming timeout")
            self?.reset()
        }
    }

    private func stopStopStreamingTimer() {
        stopStreamingTimer.stop()
    }

    // MARK: - BLE Write Helpers

    private func writeToCharacteristic(_ characteristic: CBCharacteristic?, data: Data) {
        guard let characteristic, let peripheral else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func sendProtobuf(characteristic: CBCharacteristic?, featureId: UInt8, actionId: UInt8, payload: Data) {
        let packets = GoProProtobuf.frameMessage(featureId: featureId, actionId: actionId, payload: payload)
        for packet in packets {
            writeToCharacteristic(characteristic, data: packet)
        }
    }

    private func sendTlvCommand(_ command: Data) {
        // TLV commands are written directly to the characteristic — no additional framing.
        // The first byte of the command IS the length byte.
        writeToCharacteristic(commandChar, data: command)
    }

    // MARK: - Command Senders

    private func sendStartScan() {
        let payload = GoProProtobuf.buildRequestStartScan()
        sendProtobuf(
            characteristic: networkMgmtCommandChar,
            featureId: networkMgmtFeatureId,
            actionId: startScanActionId,
            payload: payload
        )
        setState(state: .scanning)
    }

    private func sendGetApEntries(scanId: Int32) {
        let payload = GoProProtobuf.buildRequestGetApEntries(startIndex: 0, maxEntries: 100, scanId: scanId)
        sendProtobuf(
            characteristic: networkMgmtCommandChar,
            featureId: networkMgmtFeatureId,
            actionId: getApEntriesActionId,
            payload: payload
        )
    }

    private func connectToWifiFromScanResults() {
        guard let wifiSsid else {
            logger.error("gopro-device: connectToWifiFromScanResults called but wifiSsid is nil")
            return
        }
        logger.info("gopro-device: connectToWifiFromScanResults — looking for '\(wifiSsid)' in \(scanEntries.count) entries")
        for entry in scanEntries {
            logger.info("gopro-device:   scan entry: '\(entry.ssid)' flags=0x\(String(entry.flags, radix: 16)) configured=\(entry.isConfigured) associated=\(entry.isAssociated)")
        }
        // Find the target network in scan results
        if let entry = scanEntries.first(where: { $0.ssid == wifiSsid }) {
            if entry.isAssociated {
                // Already connected to this network — skip WiFi provisioning
                logger.info("gopro-device: GoPro already connected to \(wifiSsid), skipping WiFi setup")
                sendConfigureLiveStream()
                return
            }
            if entry.isConfigured {
                // Previously provisioned — use RequestConnect (no password needed)
                logger.info("gopro-device: Network \(wifiSsid) is configured, using RequestConnect")
                let payload = GoProProtobuf.buildRequestConnect(ssid: wifiSsid)
                sendProtobuf(
                    characteristic: networkMgmtCommandChar,
                    featureId: networkMgmtFeatureId,
                    actionId: connectActionId,
                    payload: payload
                )
                setState(state: .connectingToWifi)
                return
            }
        }
        // New network or not found in scan — use RequestConnectNew
        sendConnectToWifi()
    }

    private func sendConnectToWifi() {
        guard let wifiSsid, let wifiPassword else {
            logger.error("gopro-device: sendConnectToWifi called but wifiSsid=\(wifiSsid ?? "nil") wifiPassword=\(wifiPassword != nil ? "<set>" : "nil")")
            return
        }
        logger.info("gopro-device: sendConnectToWifi isFirstWifiConnect=\(isFirstWifiConnect) ssid='\(wifiSsid)' passwordLength=\(wifiPassword.count)")
        let payload: Data
        if isFirstWifiConnect {
            payload = GoProProtobuf.buildRequestConnectNew(ssid: wifiSsid, password: wifiPassword)
            sendProtobuf(
                characteristic: networkMgmtCommandChar,
                featureId: networkMgmtFeatureId,
                actionId: connectNewActionId,
                payload: payload
            )
        } else {
            payload = GoProProtobuf.buildRequestConnect(ssid: wifiSsid)
            sendProtobuf(
                characteristic: networkMgmtCommandChar,
                featureId: networkMgmtFeatureId,
                actionId: connectActionId,
                payload: payload
            )
        }
        setState(state: .connectingToWifi)
    }

    private func sendConfigureLiveStream() {
        guard let rtmpUrl else { return }
        // Official SDK sends shutter OFF before configuring livestream
        sendTlvCommand(GoProProtobuf.shutterOff)
        // Small delay to let shutter off complete before configuring
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let rtmpUrl = self.rtmpUrl else { return }
            let payload = GoProProtobuf.buildRequestSetLiveStreamMode(
                url: rtmpUrl,
                encode: false,
                windowSize: self.resolution,
                minimumBitrate: self.minimumBitrate,
                maximumBitrate: self.maximumBitrate,
                startingBitrate: self.startingBitrate
            )
            self.sendProtobuf(
                characteristic: self.commandChar,
                featureId: livestreamFeatureId,
                actionId: setLiveStreamModeActionId,
                payload: payload
            )
            self.setState(state: .configuringStream)
        }
    }

    private func sendGetLiveStreamStatus() {
        let payload = GoProProtobuf.buildRequestGetLiveStreamStatus(registerForUpdates: true)
        sendProtobuf(
            characteristic: queryChar,
            featureId: getLiveStreamStatusFeatureId,
            actionId: getLiveStreamStatusActionId,
            payload: payload
        )
        setState(state: .pollingStatus)
    }

    private func sendShutterOn() {
        sendTlvCommand(GoProProtobuf.shutterOn)
        setState(state: .startingStream)
    }

    private func sendShutterOff() {
        sendTlvCommand(GoProProtobuf.shutterOff)
    }

    private func retryWifiOrFail() {
        wifiRetryCount += 1
        if wifiRetryCount <= maxWifiRetries {
            logger.info("gopro-device: WiFi retry \(wifiRetryCount)/\(maxWifiRetries) in 5s...")
            wifiRetryTimer.startSingleShot(timeout: 5) { [weak self] in
                self?.sendConnectToWifi()
            }
        } else {
            logger.error("gopro-device: WiFi retries exhausted after \(maxWifiRetries) attempts")
            setState(state: .wifiSetupFailed)
        }
    }

    private static func provisioningStateName(_ state: Int) -> String {
        switch state {
        case 0: return "UNKNOWN"
        case 1: return "NEVER_STARTED"
        case 2: return "STARTED"
        case 3: return "ABORTED_BY_SYSTEM"
        case 4: return "CANCELLED_BY_USER"
        case 5: return "SUCCESS_NEW_AP"
        case 6: return "SUCCESS_OLD_AP"
        case 7: return "ERROR_FAILED_TO_ASSOCIATE"
        case 8: return "ERROR_PASSWORD_AUTH"
        case 9: return "ERROR_EULA_BLOCKING"
        case 10: return "ERROR_NO_INTERNET"
        case 11: return "ERROR_UNSUPPORTED_TYPE"
        default: return "UNKNOWN(\(state))"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension GoProDevice: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager?.scanForPeripherals(withServices: [goProServiceUUID])
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData _: [String: Any],
                        rssi _: NSNumber)
    {
        guard peripheral.identifier == deviceId else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
        startStartStreamingTimer()
        setState(state: .connecting)
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        setState(state: .discoveringServices)
        peripheral.discoverServices(nil)
    }

    func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
        logger.info("gopro-device: Failed to connect: \(error?.localizedDescription ?? "unknown")")
        reset()
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error _: Error?) {
        logger.info("gopro-device: Disconnected")
        if state == .stoppingStream {
            reset()
        } else if state != .idle {
            reset()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension GoProDevice: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error _: Error?)
    {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            switch char.uuid {
            case commandUUID:
                commandChar = char
            case commandResponseUUID:
                commandResponseChar = char
            case queryUUID:
                queryChar = char
            case queryResponseUUID:
                queryResponseChar = char
            case networkMgmtCommandUUID:
                networkMgmtCommandChar = char
            case networkMgmtResponseUUID:
                networkMgmtResponseChar = char
            default:
                break
            }
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                expectedSubscriptions += 1
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    func peripheral(_: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?)
    {
        if let error {
            logger.info("gopro-device: Notify error for \(characteristic.uuid): \(error)")
            return
        }
        subscribedCount += 1
        logger.debug("gopro-device: Subscribed \(subscribedCount)/\(expectedSubscriptions) (\(characteristic.uuid))")
        if subscribedCount >= expectedSubscriptions, state == .discoveringServices {
            setState(state: .subscribing)
            // All subscribed — start WiFi scan
            sendStartScan()
        }
    }

    func peripheral(_: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?)
    {
        guard error == nil, let value = characteristic.value, !value.isEmpty else { return }
        handleNotification(characteristicUUID: characteristic.uuid, data: value)
    }

    func peripheral(_: CBPeripheral,
                    didWriteValueFor _: CBCharacteristic,
                    error: Error?)
    {
        if let error {
            logger.info("gopro-device: Write error: \(error)")
        }
    }
}

// MARK: - Response Handling

extension GoProDevice {
    private func handleNotification(characteristicUUID: CBUUID, data: Data) {
        guard !data.isEmpty else { return }
        let header = data[0]
        let headerType = (header & 0x60) >> 5 // bits 6-5

        if headerType == 0 {
            // General 5-bit header: single-packet message
            // Bits 0-4 = message length (excluding header byte)
            let length = Int(header & 0x1F)
            guard data.count >= 1 + length else { return }
            let payload = Data(data[1 ..< 1 + length])
            pendingResponsePackets[characteristicUUID] = nil
            handleAssembledResponse(characteristicUUID: characteristicUUID, data: payload)
            return
        }

        let isContinuation = (header & 0x80) != 0
        if isContinuation {
            pendingResponsePackets[characteristicUUID]?.append(data)
        } else {
            // Start of extended message
            pendingResponsePackets[characteristicUUID] = [data]
        }

        // Try to reassemble extended messages
        guard let packets = pendingResponsePackets[characteristicUUID] else { return }

        // Determine expected total length from the first packet
        let firstPacket = packets[0]
        let firstHeader = firstPacket[0]
        let extHeaderType = (firstHeader & 0x60) >> 5
        var totalLength: Int
        var payloadStart: Int
        if extHeaderType == 1 {
            // 13-bit extended: length in bits 0-4 of byte 0 + byte 1
            guard firstPacket.count >= 2 else { return }
            totalLength = (Int(firstHeader & 0x1F) << 8) | Int(firstPacket[1])
            payloadStart = 2
        } else {
            // 16-bit extended: length in bytes 1-2
            guard firstPacket.count >= 3 else { return }
            totalLength = (Int(firstPacket[1]) << 8) | Int(firstPacket[2])
            payloadStart = 3
        }

        // Collect all payload bytes
        var assembled = Data()
        for (i, packet) in packets.enumerated() {
            if i == 0 {
                if payloadStart < packet.count {
                    assembled.append(packet[payloadStart...])
                }
            } else {
                // Continuation: skip first byte (0x80)
                if packet.count > 1 {
                    assembled.append(packet[1...])
                }
            }
        }

        guard assembled.count >= totalLength else { return } // Still waiting for more packets
        pendingResponsePackets[characteristicUUID] = nil
        handleAssembledResponse(characteristicUUID: characteristicUUID, data: Data(assembled.prefix(totalLength)))
    }

    private func handleAssembledResponse(characteristicUUID: CBUUID, data: Data) {
        switch characteristicUUID {
        case networkMgmtResponseUUID:
            handleNetworkMgmtResponse(data: data)
        case commandResponseUUID:
            handleCommandResponse(data: data)
        case queryResponseUUID:
            handleQueryResponse(data: data)
        default:
            break
        }
    }

    private func handleNetworkMgmtResponse(data: Data) {
        guard data.count >= 2 else {
            logger.error("gopro-device: Network mgmt response too short (\(data.count) bytes)")
            return
        }
        let featureId = data[0]
        let actionId = data[1]
        let payload = data.count > 2 ? data[2...] : Data()
        let fields = GoProProtobuf.decodeFields(data: Data(payload))

        logger.info("gopro-device: Network mgmt response F=0x\(String(featureId, radix: 16)) A=0x\(String(actionId, radix: 16)) payloadSize=\(payload.count) fieldCount=\(fields.count)")

        // Action ID 0x82 = ResponseStartScanning
        if actionId == 0x82 {
            // Check result
            if let resultField = fields.first(where: { $0.fieldNumber == 1 }) {
                let result = Int(GoProProtobuf.getVarintValue(field: resultField))
                if result != 1 {
                    logger.info("gopro-device: Scan start failed: result=\(result)")
                    // Fall back to direct connect
                    sendConnectToWifi()
                }
            }
            // Wait for scan notification (0x0B)
            return
        }

        // Action ID 0x0B = NotifStartScanning
        if actionId == 0x0B {
            if let stateField = fields.first(where: { $0.fieldNumber == 1 }) {
                let scanState = Int(GoProProtobuf.getVarintValue(field: stateField))
                // SCANNING_SUCCESS = 5
                if scanState == 5 {
                    if let scanIdField = fields.first(where: { $0.fieldNumber == 2 }) {
                        currentScanId = Int32(GoProProtobuf.getVarintValue(field: scanIdField))
                        logger.info("gopro-device: Scan complete, scanId=\(currentScanId)")
                        sendGetApEntries(scanId: currentScanId)
                    }
                } else if scanState >= 3 {
                    // Scan failed — fall back to direct connect
                    logger.info("gopro-device: Scan failed (state \(scanState)), falling back to direct connect")
                    sendConnectToWifi()
                }
                // States 0, 1, 2 are transitional
            }
            return
        }

        // Action ID 0x83 = ResponseGetApEntries
        if actionId == 0x83 {
            if let resultField = fields.first(where: { $0.fieldNumber == 1 }) {
                let result = Int(GoProProtobuf.getVarintValue(field: resultField))
                if result != 1 {
                    logger.info("gopro-device: Get AP entries failed: result=\(result)")
                    sendConnectToWifi()
                    return
                }
            }
            // Parse scan entries from the full payload (not just fields — need nested message parsing)
            scanEntries = GoProProtobuf.parseScanEntries(data: Data(payload))
            logger.info("gopro-device: Found \(scanEntries.count) networks:")
            for entry in scanEntries {
                logger.info("  \(entry.ssid) bars=\(entry.signalStrengthBars) configured=\(entry.isConfigured) associated=\(entry.isAssociated)")
            }
            connectToWifiFromScanResults()
            return
        }

        // Action ID 0x84 = ResponseConnect, 0x85 = ResponseConnectNew
        if actionId == 0x84 || actionId == 0x85 {
            if let resultField = fields.first(where: { $0.fieldNumber == 1 }) {
                let result = Int(GoProProtobuf.getVarintValue(field: resultField))
                let provState = fields.first(where: { $0.fieldNumber == 2 }).map { Int(GoProProtobuf.getVarintValue(field: $0)) }
                let timeout = fields.first(where: { $0.fieldNumber == 3 }).map { Int(GoProProtobuf.getVarintValue(field: $0)) }
                logger.info("gopro-device: WiFi connect response (0x\(String(actionId, radix: 16))): result=\(result) provisioningState=\(provState ?? -1) timeout=\(timeout ?? -1)s")
                if result != 1 {
                    logger.error("gopro-device: WiFi connect initial response failed: result=\(result)")
                    retryWifiOrFail()
                    return
                }
            }
            // Success — wait for provisioning notifications
            return
        }

        // Action ID 0x0C = NotifProvisioningState notification
        if actionId == 0x0C {
            if let stateField = fields.first(where: { $0.fieldNumber == 1 }) {
                let provisioningState = Int(GoProProtobuf.getVarintValue(field: stateField))
                logger.info("gopro-device: Provisioning state: \(provisioningState) (\(Self.provisioningStateName(provisioningState)))")
                if provisioningState == 5 || provisioningState == 6 {
                    isFirstWifiConnect = false
                    logger.info("gopro-device: WiFi connected successfully")
                    sendConfigureLiveStream()
                } else if provisioningState == 2 {
                    logger.debug("gopro-device: WiFi provisioning started, waiting...")
                } else if provisioningState >= 3 {
                    logger.info("gopro-device: WiFi setup failed (state \(provisioningState))")
                    retryWifiOrFail()
                }
            }
        }
    }

    private func handleCommandResponse(data: Data) {
        guard data.count >= 2 else { return }
        let featureId = data[0]
        let actionId = data[1]
        let payload = data.count > 2 ? data[2...] : Data()
        let fields = GoProProtobuf.decodeFields(data: Data(payload))

        logger.debug("gopro-device: Command response F=\(featureId) A=\(actionId)")

        // Response to SetLiveStreamMode (action 0xF9 = response to 0x79)
        if featureId == livestreamFeatureId, actionId == 0xF9 {
            if let resultField = fields.first(where: { $0.fieldNumber == 1 }) {
                let result = Int(GoProProtobuf.getVarintValue(field: resultField))
                // From response_generic.proto: RESULT_SUCCESS = 1
                if result == 1 {
                    logger.info("gopro-device: Livestream configured successfully")
                    sendGetLiveStreamStatus()
                } else {
                    logger.info("gopro-device: Livestream config failed: result=\(result)")
                    reset()
                }
            } else {
                // No result field — assume success
                sendGetLiveStreamStatus()
            }
        }

        // TLV command response: [commandId, status]
        // Shutter command ID is 0x01, status 0 = success
        if data.count >= 2, data[0] == 0x01 {
            let status = data[1]
            if status == 0 {
                if state == .startingStream {
                    logger.info("gopro-device: Shutter on success — streaming")
                    setState(state: .streaming)
                    stopStartStreamingTimer()
                } else if state == .stoppingStream {
                    logger.info("gopro-device: Shutter off success")
                    reset()
                }
            }
        }
    }

    private func handleQueryResponse(data: Data) {
        guard data.count >= 2 else { return }
        let featureId = data[0]
        let actionId = data[1]
        let payload = data.count > 2 ? data[2...] : Data()
        let fields = GoProProtobuf.decodeFields(data: Data(payload))

        logger.debug("gopro-device: Query response F=\(featureId) A=\(actionId)")

        // NotifyLiveStreamStatus (action 0xF4 or 0xF5)
        if featureId == getLiveStreamStatusFeatureId,
           actionId == 0xF4 || actionId == 0xF5
        {
            if let statusField = fields.first(where: { $0.fieldNumber == 1 }) {
                let liveStatus = GoProLiveStreamStatus(rawValue: Int(GoProProtobuf.getVarintValue(field: statusField)))
                logger.info("gopro-device: Live stream status: \(liveStatus)")
                switch liveStatus {
                case .ready:
                    // Official SDK waits 2 seconds after READY before sending shutter ON
                    logger.info("gopro-device: Live stream ready, waiting 2s before starting...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.sendShutterOn()
                    }
                case .streaming:
                    setState(state: .streaming)
                    stopStartStreamingTimer()
                case .failedStayOn, .unavailable, .completeStayOn:
                    logger.info("gopro-device: Live stream ended or unavailable")
                    reset()
                case .reconnecting:
                    logger.info("gopro-device: Live stream reconnecting")
                    // Keep waiting
                case .idle, .config:
                    // Still setting up — keep waiting for next notification
                    break
                case .unknown:
                    break
                }
            }
        }
    }
}
