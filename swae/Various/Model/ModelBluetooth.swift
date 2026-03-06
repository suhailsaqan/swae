import CoreBluetooth

let bluetoothNotAllowedMessage = "⚠️ Swae is not allowed to use Bluetooth"

extension Model: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_: CBCentralManager) {
        bluetoothAllowed = CBCentralManager.authorization == .allowedAlways
    }
}
