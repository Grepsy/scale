import Foundation

/// Unit the scale is configured to display. The scale is set up through Zepp Life;
/// we only report it back so the UI can match what the scale's own display shows.
public enum ScaleDisplayUnit: String, Codable, Sendable {
    case kilograms
    case pounds
    case jin
}

/// One decoded Bluetooth advertisement from a Mi Body Composition Scale 2 (XMTZC05HM).
public struct ScaleReading: Equatable, Sendable {
    /// Raw 16-bit weight value as broadcast. Its scale depends on `displayUnit`.
    public var rawWeight: UInt16
    public var displayUnit: ScaleDisplayUnit
    /// Bioelectrical impedance in ohms, present once the scale has finished the
    /// body-composition measurement (only when standing barefoot).
    public var impedance: Int?
    /// The weight has settled; the scale's display stops flickering at this point.
    public var isStabilized: Bool
    /// The user has stepped off; the scale keeps re-broadcasting the last result for a while.
    public var isWeightRemoved: Bool
    /// Timestamp from the scale's own clock (set by Zepp Life). `nil` if the scale flags it as invalid.
    public var scaleTimestamp: DateComponents?

    public init(rawWeight: UInt16, displayUnit: ScaleDisplayUnit, impedance: Int?, isStabilized: Bool,
                isWeightRemoved: Bool, scaleTimestamp: DateComponents?) {
        self.rawWeight = rawWeight
        self.displayUnit = displayUnit
        self.impedance = impedance
        self.isStabilized = isStabilized
        self.isWeightRemoved = isWeightRemoved
        self.scaleTimestamp = scaleTimestamp
    }

    /// Weight in the unit shown on the scale's display.
    public var displayWeight: Double {
        switch displayUnit {
        case .kilograms: return Double(rawWeight) / 200
        case .pounds, .jin: return Double(rawWeight) / 100
        }
    }

    public var weightInKilograms: Double {
        switch displayUnit {
        case .kilograms: return Double(rawWeight) / 200
        case .jin: return Double(rawWeight) / 200 // 1 jin = 0.5 kg, raw is jin * 100
        case .pounds: return Double(rawWeight) / 100 * 0.45359237
        }
    }
}

/// Decoder for the "Body Composition" (0x181B) service data the scale broadcasts.
///
/// The scale does not need a connection: every packet is a BLE advertisement carrying
/// 13 bytes of service data. See docs/PROTOCOL.md for the layout.
public enum MiScaleAdvertisement {
    /// 16-bit Bluetooth SIG UUID of the Body Composition service.
    public static let serviceUUID = "181B"

    public static func parse(_ data: Data) -> ScaleReading? {
        var bytes = [UInt8](data)
        // Some BLE stacks hand over the service data with the UUID (1B 18) still in front.
        if bytes.count == 15, bytes[0] == 0x1B, bytes[1] == 0x18 {
            bytes.removeFirst(2)
        }
        guard bytes.count == 13 else { return nil }

        func uint16(at i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }

        let control0 = bytes[0]
        let control1 = bytes[1]

        let isPounds = control0 & 0x01 != 0
        let isJin = control0 & 0x10 != 0
        let hasImpedance = control1 & 0x02 != 0
        let isStabilized = control1 & 0x20 != 0
        let isDateInvalid = control1 & 0x40 != 0
        let isWeightRemoved = control1 & 0x80 != 0

        let unit: ScaleDisplayUnit = isPounds ? .pounds : (isJin ? .jin : .kilograms)

        var timestamp: DateComponents?
        if !isDateInvalid {
            timestamp = DateComponents(year: Int(uint16(at: 2)), month: Int(bytes[4]), day: Int(bytes[5]),
                                       hour: Int(bytes[6]), minute: Int(bytes[7]), second: Int(bytes[8]))
        }

        let rawImpedance = uint16(at: 9)
        // 0 and 0xFFFE/0xFFFF show up while the measurement is still running; anything
        // above ~3000 Ω is not a real body.
        let impedance = hasImpedance && rawImpedance > 0 && rawImpedance < 3000 ? Int(rawImpedance) : nil

        return ScaleReading(rawWeight: uint16(at: 11), displayUnit: unit, impedance: impedance,
                            isStabilized: isStabilized, isWeightRemoved: isWeightRemoved,
                            scaleTimestamp: timestamp)
    }
}
