import CoreBluetooth
import Foundation

/// Connects to a GoPro via BLE, scans for WiFi networks, and returns the results.
/// This is a standalone scanner used by the UI to populate the WiFi network picker.
class GoProWifiScanner: NSObject, ObservableObject {
    @Published var scanEntries: [GoProScanEntry] = []
    @Published var isScanning = false
    @Published var error: String?

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var deviceId: UUID?
    private var networkMgmtCommandChar: CBCharacteristic?
    private var networkMgmtResponseChar: CBCharacteristic?
    private var pendingResponsePackets: [CBUUID: [Data]] = [:]
    private var subscribedCount = 0
    private var expectedSubscriptions = 0
    private var currentScanId: Int32 = 0
    private var scanCommandSent = false
    private let timeoutTimer = SimpleTimer(queue: .main)

    private let goProServiceUUID = CBUUID(string: "FEA6")
    private let networkMgmtCommandUUID = CBUUID(string: "b5f90091-aa8d-11e3-9046-0002a5d5c51b")
    private let networkMgmtResponseUUID = CBUUID(string: "b5f90092-aa8d-11e3-9046-0002a5d5c51b")

    func startScan(deviceId: UUID) {
        stop()
        self.deviceId = deviceId
        scanEntries = []
        error = nil
        isScanning = true
        logger.info("gopro-wifi-scanner: Starting scan for device \(deviceId)")
        timeoutTimer.startSingleShot(timeout: 30) { [weak self] in
            logger.error("gopro-wifi-scanner: Scan timed out — subscribedCount=\(self?.subscribedCount ?? -1)/\(self?.expectedSubscriptions ?? -1) scanCommandSent=\(self?.scanCommandSent ?? false) networkMgmtCommandChar=\(self?.networkMgmtCommandChar != nil ? "found" : "nil") networkMgmtResponseChar=\(self?.networkMgmtResponseChar != nil ? "found" : "nil")")
            self?.error = "Scan timed out"
            self?.stop()
        }
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func stop() {
        timeoutTimer.stop()
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        centralManager = nil
        peripheral = nil
        networkMgmtCommandChar = nil
        networkMgmtResponseChar = nil
        pendingResponsePackets = [:]
        subscribedCount = 0
        expectedSubscriptions = 0
        scanCommandSent = false
        isScanning = false
    }

    private func sendStartScan() {
        guard let char = networkMgmtCommandChar, let peripheral else {
            logger.error("gopro-wifi-scanner: Cannot send scan — networkMgmtCommandChar is nil")
            error = "BLE setup incomplete — network management characteristic not found"
            stop()
            return
        }
        logger.info("gopro-wifi-scanner: Sending RequestStartScan")
        let payload = GoProProtobuf.buildRequestStartScan()
        let packets = GoProProtobuf.frameMessage(featureId: 0x02, actionId: 0x02, payload: payload)
        for packet in packets {
            peripheral.writeValue(packet, for: char, type: .withResponse)
        }
    }

    private func sendGetApEntries(scanId: Int32) {
        guard let char = networkMgmtCommandChar, let peripheral else {
            logger.error("gopro-wifi-scanner: Cannot send GetApEntries — networkMgmtCommandChar is nil")
            error = "BLE setup incomplete"
            stop()
            return
        }
        logger.info("gopro-wifi-scanner: Sending RequestGetApEntries (scanId=\(scanId))")
        let payload = GoProProtobuf.buildRequestGetApEntries(startIndex: 0, maxEntries: 100, scanId: scanId)
        let packets = GoProProtobuf.frameMessage(featureId: 0x02, actionId: 0x03, payload: payload)
        for packet in packets {
            peripheral.writeValue(packet, for: char, type: .withResponse)
        }
    }

    private func startScanIfReady() {
        guard !scanCommandSent else { return }
        guard networkMgmtCommandChar != nil else {
            logger.error("gopro-wifi-scanner: All subscriptions complete but networkMgmtCommandChar is nil")
            error = "GoPro network management service not found"
            stop()
            return
        }
        scanCommandSent = true
        sendStartScan()
    }

    private func handleResponse(data: Data) {
        guard data.count >= 2 else {
            logger.error("gopro-wifi-scanner: Response too short (\(data.count) bytes): \(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
            return
        }
        let featureId = data[0]
        let actionId = data[1]
        let payload = data.count > 2 ? Data(data[2...]) : Data()
        let fields = GoProProtobuf.decodeFields(data: payload)

        logger.info("gopro-wifi-scanner: Response featureId=0x\(String(featureId, radix: 16)) actionId=0x\(String(actionId, radix: 16)) payloadSize=\(payload.count) fieldCount=\(fields.count)")
        for (i, field) in fields.enumerated() {
            logger.debug("gopro-wifi-scanner:   field[\(i)] number=\(field.fieldNumber) wireType=\(field.wireType) dataSize=\(field.data.count)")
        }

        // ResponseStartScanning
        if actionId == 0x82 {
            if let resultField = fields.first(where: { $0.fieldNumber == 1 }) {
                let result = Int(GoProProtobuf.getVarintValue(field: resultField))
                logger.info("gopro-wifi-scanner: StartScan result=\(result)")
                if result != 1 {
                    error = "WiFi scan failed to start (result=\(result))"
                    stop()
                }
            }
            return
        }

        // NotifStartScanning
        if actionId == 0x0B {
            if let stateField = fields.first(where: { $0.fieldNumber == 1 }) {
                let scanState = Int(GoProProtobuf.getVarintValue(field: stateField))
                let totalEntries = fields.first(where: { $0.fieldNumber == 3 }).map { Int(GoProProtobuf.getVarintValue(field: $0)) }
                logger.info("gopro-wifi-scanner: Scan state=\(scanState) totalEntries=\(totalEntries ?? -1)")
                if scanState == 5 { // SCANNING_SUCCESS
                    if let scanIdField = fields.first(where: { $0.fieldNumber == 2 }) {
                        currentScanId = Int32(GoProProtobuf.getVarintValue(field: scanIdField))
                        logger.info("gopro-wifi-scanner: Scan complete, scanId=\(currentScanId), totalEntries=\(totalEntries ?? -1)")
                        sendGetApEntries(scanId: currentScanId)
                    } else {
                        logger.error("gopro-wifi-scanner: Scan succeeded but no scan_id in notification. Fields: \(fields.map { "f\($0.fieldNumber)=\($0.wireType)" }.joined(separator: ", "))")
                        error = "Scan completed but no results ID received"
                        stop()
                    }
                } else if scanState >= 3 {
                    logger.error("gopro-wifi-scanner: Scan failed with state=\(scanState)")
                    error = "WiFi scan failed (state=\(scanState))"
                    stop()
                }
                // States 0, 1, 2 are transitional — keep waiting
            } else {
                logger.error("gopro-wifi-scanner: NotifStartScanning missing state field. Fields: \(fields.map { "f\($0.fieldNumber)=\($0.wireType)" }.joined(separator: ", "))")
            }
            return
        }

        // ResponseGetApEntries
        if actionId == 0x83 {
            if let resultField = fields.first(where: { $0.fieldNumber == 1 }) {
                let result = Int(GoProProtobuf.getVarintValue(field: resultField))
                logger.info("gopro-wifi-scanner: GetApEntries result=\(result)")
                if result != 1 {
                    error = "Failed to get scan results (result=\(result))"
                    stop()
                    return
                }
            } else {
                logger.warning("gopro-wifi-scanner: GetApEntries response missing result field")
            }
            let field3Count = fields.filter({ $0.fieldNumber == 3 && $0.wireType == 2 }).count
            logger.info("gopro-wifi-scanner: GetApEntries payload has \(fields.count) fields, \(field3Count) are ScanEntry (field 3, wireType 2)")
            logger.info("gopro-wifi-scanner: Raw payload hex (\(payload.count) bytes): \(payload.prefix(200).map { String(format: "%02x", $0) }.joined(separator: " "))")
            scanEntries = GoProProtobuf.parseScanEntries(data: payload)
            logger.info("gopro-wifi-scanner: Parsed \(scanEntries.count) networks")
            for entry in scanEntries {
                logger.info("  \(entry.ssid) bars=\(entry.signalStrengthBars) freq=\(entry.signalFrequencyMhz) flags=0x\(String(entry.flags, radix: 16)) configured=\(entry.isConfigured) associated=\(entry.isAssociated) requiresAuth=\(entry.requiresAuth)")
            }
            isScanning = false
            timeoutTimer.stop()
            // Disconnect — we only needed the scan results
            if let peripheral {
                centralManager?.cancelPeripheralConnection(peripheral)
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension GoProWifiScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("gopro-wifi-scanner: BLE state: \(central.state.rawValue)")
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [goProServiceUUID])
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData _: [String: Any],
                        rssi _: NSNumber)
    {
        guard peripheral.identifier == deviceId else { return }
        logger.info("gopro-wifi-scanner: Found target peripheral \(peripheral.identifier)")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("gopro-wifi-scanner: Connected, discovering services")
        peripheral.discoverServices(nil)
    }

    func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
        logger.error("gopro-wifi-scanner: Failed to connect: \(error?.localizedDescription ?? "unknown")")
        self.error = "Failed to connect to GoPro: \(error?.localizedDescription ?? "unknown")"
        stop()
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error _: Error?) {
        logger.debug("gopro-wifi-scanner: Disconnected")
    }
}

// MARK: - CBPeripheralDelegate

extension GoProWifiScanner: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: Error?) {
        guard let services = peripheral.services else { return }
        logger.debug("gopro-wifi-scanner: Discovered \(services.count) services")
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
            if char.uuid == networkMgmtCommandUUID {
                networkMgmtCommandChar = char
                logger.info("gopro-wifi-scanner: Found networkMgmtCommand char")
            }
            if char.uuid == networkMgmtResponseUUID {
                networkMgmtResponseChar = char
                logger.info("gopro-wifi-scanner: Found networkMgmtResponse char")
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
            logger.info("gopro-wifi-scanner: Subscription error for \(characteristic.uuid): \(error)")
            return
        }
        subscribedCount += 1
        logger.debug("gopro-wifi-scanner: Subscribed \(subscribedCount)/\(expectedSubscriptions) (\(characteristic.uuid))")
        if subscribedCount >= expectedSubscriptions {
            startScanIfReady()
        }
    }

    func peripheral(_: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?)
    {
        if let error {
            logger.error("gopro-wifi-scanner: Notification error: \(error)")
            return
        }
        guard let value = characteristic.value, !value.isEmpty else { return }
        guard characteristic.uuid == networkMgmtResponseUUID else {
            logger.debug("gopro-wifi-scanner: Ignoring notification from non-network-mgmt char \(characteristic.uuid)")
            return
        }

        logger.debug("gopro-wifi-scanner: Raw BLE notification (\(value.count) bytes): \(value.prefix(40).map { String(format: "%02x", $0) }.joined(separator: " "))")

        let header = value[0]
        let headerType = (header & 0x60) >> 5

        if headerType == 0 {
            let length = Int(header & 0x1F)
            guard value.count >= 1 + length else { return }
            let payload = Data(value[1 ..< 1 + length])
            pendingResponsePackets[characteristic.uuid] = nil
            handleResponse(data: payload)
            return
        }

        let isContinuation = (header & 0x80) != 0
        let uuid = characteristic.uuid
        if isContinuation {
            pendingResponsePackets[uuid]?.append(value)
        } else {
            pendingResponsePackets[uuid] = [value]
        }

        guard let packets = pendingResponsePackets[uuid] else { return }
        let firstPacket = packets[0]
        let firstHeader = firstPacket[0]
        let extHeaderType = (firstHeader & 0x60) >> 5
        var totalLength: Int
        var payloadStart: Int
        if extHeaderType == 1 {
            guard firstPacket.count >= 2 else { return }
            totalLength = (Int(firstHeader & 0x1F) << 8) | Int(firstPacket[1])
            payloadStart = 2
        } else {
            guard firstPacket.count >= 3 else { return }
            totalLength = (Int(firstPacket[1]) << 8) | Int(firstPacket[2])
            payloadStart = 3
        }

        var assembled = Data()
        for (i, packet) in packets.enumerated() {
            if i == 0 {
                if payloadStart < packet.count { assembled.append(packet[payloadStart...]) }
            } else {
                if packet.count > 1 { assembled.append(packet[1...]) }
            }
        }

        guard assembled.count >= totalLength else { return }
        pendingResponsePackets[uuid] = nil
        handleResponse(data: Data(assembled.prefix(totalLength)))
    }
}
