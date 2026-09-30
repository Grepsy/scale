import CoreBluetooth
import Foundation
import MiScaleKit

/// Listens for the scale's BLE advertisements. The scale never needs a connection:
/// every reading is carried in the advertisement's 0x181B service data.
@MainActor
final class ScaleScanner: NSObject, ObservableObject {
    enum State: Equatable {
        case starting
        case scanning
        case stopped
        case poweredOff
        case unauthorized
        case unsupported
    }

    @Published private(set) var state: State = .stopped

    /// Called for every decoded advertisement with the peripheral's (per-device) identifier.
    var onReading: ((ScaleReading, UUID) -> Void)?

    private static let serviceUUID = CBUUID(string: MiScaleAdvertisement.serviceUUID)
    private var central: CBCentralManager?
    private var wantsToScan = false

    func start() {
        wantsToScan = true
        if let central {
            startIfReady(central)
        } else {
            state = .starting
            // Created lazily so the Bluetooth permission prompt appears on first use.
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func stop() {
        wantsToScan = false
        central?.stopScan()
        if state == .scanning { state = .stopped }
    }

    private func startIfReady(_ central: CBCentralManager) {
        guard wantsToScan, central.state == .poweredOn else { return }
        // Scan without a service filter: the scale puts 0x181B in its service data,
        // which CoreBluetooth's service filter doesn't reliably match. Duplicates are
        // needed because the scale re-advertises the changing weight many times a second.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        state = .scanning
    }

    private func updateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = .stopped
            startIfReady(central)
        case .poweredOff: state = .poweredOff
        case .unauthorized: state = .unauthorized
        case .unsupported: state = .unsupported
        default: state = .starting
        }
    }

    private func handle(_ advertisementData: [String: Any], from peripheral: CBPeripheral) {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let payload = serviceData[Self.serviceUUID],
              let reading = MiScaleAdvertisement.parse(payload)
        else { return }
        onReading?(reading, peripheral.identifier)
    }
}

extension ScaleScanner: CBCentralManagerDelegate {
    // The central manager delivers on the main queue, so we're already on the main actor.
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { updateState(central) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated { handle(advertisementData, from: peripheral) }
    }
}
