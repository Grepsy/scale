import Foundation

/// A finished weigh-in, ready to be stored.
public struct CompletedMeasurement: Equatable, Sendable {
    /// Stable identifier for this weigh-in, used to de-duplicate the scale's repeated
    /// broadcasts and as the HealthKit sync identifier.
    public var id: String
    public var weightKg: Double
    public var displayWeight: Double
    public var displayUnit: ScaleDisplayUnit
    public var impedance: Int?
    public var scaleTimestamp: DateComponents?
}

/// Turns the stream of advertisements into weigh-in events.
///
/// While someone stands on the scale it broadcasts several packets per second:
/// unstable weights, then a stabilized weight, then (if barefoot) a stabilized weight
/// with impedance. After stepping off it keeps repeating the final packet with the
/// "weight removed" flag for a while. A weigh-in is complete when we see a stabilized
/// packet with impedance, or a stabilized packet with the removed flag (no impedance,
/// e.g. wearing socks).
public struct MeasurementTracker {
    public enum Event: Equatable, Sendable {
        case measuring(weightKg: Double)
        case stabilized(weightKg: Double)
        case completed(CompletedMeasurement)
    }

    /// How long a completed weigh-in suppresses repeats of the same weight.
    public var duplicateWindow: TimeInterval = 120

    private var lastCompleted: (id: String, rawWeight: UInt16, at: Date)?

    public init() {}

    public mutating func ingest(_ reading: ScaleReading, now: Date = Date()) -> Event? {
        guard reading.rawWeight > 0 else { return nil }

        let id = Self.identifier(for: reading, now: now)
        let recent = lastCompleted.flatMap { now.timeIntervalSince($0.at) < duplicateWindow ? $0 : nil }

        if reading.isStabilized && (reading.impedance != nil || reading.isWeightRemoved) {
            if let recent, recent.id == id || recent.rawWeight == reading.rawWeight { return nil }
            lastCompleted = (id, reading.rawWeight, now)
            return .completed(CompletedMeasurement(
                id: id, weightKg: reading.weightInKilograms, displayWeight: reading.displayWeight,
                displayUnit: reading.displayUnit, impedance: reading.impedance,
                scaleTimestamp: reading.scaleTimestamp))
        }

        // Stepped off without a completed measurement, or echoes of the last one.
        if reading.isWeightRemoved { return nil }
        if let recent, recent.rawWeight == reading.rawWeight { return nil }

        return reading.isStabilized
            ? .stabilized(weightKg: reading.weightInKilograms)
            : .measuring(weightKg: reading.weightInKilograms)
    }

    static func identifier(for reading: ScaleReading, now: Date) -> String {
        if let t = reading.scaleTimestamp, let y = t.year, let mo = t.month, let d = t.day,
           let h = t.hour, let mi = t.minute, let s = t.second {
            return String(format: "miscale-%04ld%02ld%02ld%02ld%02ld%02ld-%ld", y, mo, d, h, mi, s, Int(reading.rawWeight))
        }
        // No usable scale clock: fall back to the minute we received it.
        return "miscale-t\(Int(now.timeIntervalSince1970 / 60))-\(reading.rawWeight)"
    }
}
