import XCTest
@testable import MiScaleKit

private func hex(_ s: String) -> Data {
    var data = Data()
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        data.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return data
}

final class AdvertisementTests: XCTestCase {
    // kg, stabilized + impedance, 2026-09-30 07:15:00, 500 Ω, 70.00 kg
    let finalPacket = "0222ea07091e070f00f401b036"

    func testParsesStabilizedMeasurementWithImpedance() throws {
        let r = try XCTUnwrap(MiScaleAdvertisement.parse(hex(finalPacket)))
        XCTAssertEqual(r.displayUnit, .kilograms)
        XCTAssertEqual(r.weightInKilograms, 70.0, accuracy: 1e-9)
        XCTAssertEqual(r.impedance, 500)
        XCTAssertTrue(r.isStabilized)
        XCTAssertFalse(r.isWeightRemoved)
        XCTAssertEqual(r.scaleTimestamp, DateComponents(year: 2026, month: 9, day: 30, hour: 7, minute: 15, second: 0))
    }

    func testAcceptsServiceDataWithUUIDPrefix() {
        XCTAssertEqual(MiScaleAdvertisement.parse(hex("1b18" + finalPacket)),
                       MiScaleAdvertisement.parse(hex(finalPacket)))
    }

    func testParsesPounds() throws {
        let r = try XCTUnwrap(MiScaleAdvertisement.parse(hex("0300ea07091e070f000000483c")))
        XCTAssertEqual(r.displayUnit, .pounds)
        XCTAssertEqual(r.displayWeight, 154.32, accuracy: 1e-9)
        XCTAssertEqual(r.weightInKilograms, 69.99837, accuracy: 1e-4)
        XCTAssertNil(r.impedance)
        XCTAssertFalse(r.isStabilized)
    }

    func testIgnoresImpedanceWithoutFlagAndBogusValues() throws {
        // impedance bytes set but flag clear
        XCTAssertNil(try XCTUnwrap(MiScaleAdvertisement.parse(hex("0220ea07091e070f00f401b036"))).impedance)
        // flag set but 0xFFFF
        XCTAssertNil(try XCTUnwrap(MiScaleAdvertisement.parse(hex("0222ea07091e070f00ffffb036"))).impedance)
    }

    func testInvalidDate() throws {
        XCTAssertNil(try XCTUnwrap(MiScaleAdvertisement.parse(hex("0262ea07091e070f00f401b036"))).scaleTimestamp)
    }

    func testRejectsWrongLength() {
        XCTAssertNil(MiScaleAdvertisement.parse(hex("0222ea07")))
    }
}

final class TrackerTests: XCTestCase {
    private func reading(_ raw: UInt16, stable: Bool = false, impedance: Int? = nil, removed: Bool = false) -> ScaleReading {
        ScaleReading(rawWeight: raw, displayUnit: .kilograms, impedance: impedance, isStabilized: stable,
                     isWeightRemoved: removed,
                     scaleTimestamp: DateComponents(year: 2026, month: 9, day: 30, hour: 7, minute: 15, second: 0))
    }

    func testFullWeighIn() {
        var tracker = MeasurementTracker()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(tracker.ingest(reading(0), now: t0), nil)
        XCTAssertEqual(tracker.ingest(reading(12000), now: t0), .measuring(weightKg: 60))
        XCTAssertEqual(tracker.ingest(reading(14000, stable: true), now: t0), .stabilized(weightKg: 70))

        guard case .completed(let m)? = tracker.ingest(reading(14000, stable: true, impedance: 500), now: t0) else {
            return XCTFail("expected completion")
        }
        XCTAssertEqual(m.weightKg, 70)
        XCTAssertEqual(m.impedance, 500)
        XCTAssertEqual(m.id, "miscale-20260930071500-14000")

        // Repeats while standing and after stepping off are swallowed.
        XCTAssertNil(tracker.ingest(reading(14000, stable: true, impedance: 500), now: t0 + 1))
        XCTAssertNil(tracker.ingest(reading(14000, stable: true), now: t0 + 2))
        XCTAssertNil(tracker.ingest(reading(14000, stable: true, impedance: 500, removed: true), now: t0 + 3))
    }

    func testCompletesWithoutImpedanceWhenSteppingOff() {
        var tracker = MeasurementTracker()
        XCTAssertEqual(tracker.ingest(reading(14000, stable: true)), .stabilized(weightKg: 70))
        guard case .completed(let m)? = tracker.ingest(reading(14000, stable: true, removed: true)) else {
            return XCTFail("expected completion")
        }
        XCTAssertNil(m.impedance)
    }

    func testSameWeightLaterIsNewMeasurement() {
        var tracker = MeasurementTracker()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNotNil(tracker.ingest(reading(14000, stable: true, impedance: 500), now: t0))
        XCTAssertNotNil(tracker.ingest(reading(14000, stable: true, impedance: 500), now: t0 + 600))
    }
}

final class CompositionTests: XCTestCase {
    // Expected values cross-checked against tools/miscale_sniff.py.
    func testMale() throws {
        let c = BodyComposition(weightKg: 80, heightCm: 180, age: 35, sex: .male, impedance: 500)
        XCTAssertEqual(c.bmi, 24.6914, accuracy: 1e-3)
        XCTAssertEqual(c.basalMetabolicRate, 1626.24, accuracy: 1e-2)
        XCTAssertEqual(try XCTUnwrap(c.bodyFatPercentage), 23.6538, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(c.waterPercentage), 52.3735, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(c.boneMassKg), 3.1114, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(c.muscleMassKg), 57.9655, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(c.visceralFat), 14.11, accuracy: 1e-2)
        XCTAssertEqual(try XCTUnwrap(c.leanBodyMassKg), 61.0769, accuracy: 1e-3)
    }

    func testFemale() throws {
        let c = BodyComposition(weightKg: 62, heightCm: 165, age: 52, sex: .female, impedance: 560)
        XCTAssertEqual(c.bmi, 22.7732, accuracy: 1e-3)
        XCTAssertEqual(c.basalMetabolicRate, 1109.7108, accuracy: 1e-2)
        XCTAssertEqual(try XCTUnwrap(c.bodyFatPercentage), 31.6612, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(c.waterPercentage), 48.7939, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(c.boneMassKg), 2.4385, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(c.muscleMassKg), 39.9316, accuracy: 1e-3)
    }

    func testWithoutImpedanceOnlyBMIAndBMR() {
        let c = BodyComposition(weightKg: 70, heightCm: 175, age: 30, sex: .male, impedance: nil)
        XCTAssertEqual(c.bmi, 22.8571, accuracy: 1e-3)
        XCTAssertEqual(c.basalMetabolicRate, 1525.59, accuracy: 1e-2)
        XCTAssertNil(c.bodyFatPercentage)
        XCTAssertNil(c.leanBodyMassKg)
        XCTAssertNil(c.visceralFat)
    }
}
