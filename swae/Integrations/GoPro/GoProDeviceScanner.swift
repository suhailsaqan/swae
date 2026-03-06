import CoreBluetooth

private let goProServiceUUID = CBUUID(string: "FEA6")

struct GoProDiscoveredDevice {
    let peripheral: CBPeripheral
    let name: String
}

class GoProDeviceScanner: NSObject, ObservableObject {
    static let shared = GoProDeviceScanner()
    @Published var discoveredDevices: [GoProDiscoveredDevice] = []
    private var centralManager: CBCentralManager?

    func startScanningForDevices() {
        discoveredDevices = []
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func stopScanningForDevices() {
        centralManager?.stopScan()
        centralManager = nil
    }
}

extension GoProDeviceScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [goProServiceUUID], options: nil)
        }
    }

    func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi _: NSNumber
    ) {
        guard let name = peripheral.name, name.hasPrefix("GoPro") else {
            return
        }
        guard !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) else {
            return
        }
        logger.info("gopro-scanner: Discovered \(name) (\(peripheral.identifier))")
        discoveredDevices.append(.init(peripheral: peripheral, name: name))
    }
}
