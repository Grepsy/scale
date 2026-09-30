import Foundation
import HealthKit
import MiScaleKit

/// Writes weigh-ins to Apple Health and reads the profile values body composition needs.
final class HealthKitManager {
    struct ProfileDefaults {
        var heightCm: Double?
        var birthYear: Int?
        var sex: BodyComposition.Sex?
    }

    private let store = HKHealthStore()

    private let bodyMass = HKQuantityType(.bodyMass)
    private let bmi = HKQuantityType(.bodyMassIndex)
    private let bodyFat = HKQuantityType(.bodyFatPercentage)
    private let leanBodyMass = HKQuantityType(.leanBodyMass)
    private let height = HKQuantityType(.height)

    private static let device = HKDevice(name: "Mi Body Composition Scale 2", manufacturer: "Xiaomi",
                                         model: "XMTZC05HM", hardwareVersion: nil, firmwareVersion: nil,
                                         softwareVersion: nil, localIdentifier: nil, udiDeviceIdentifier: nil)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(
            toShare: [bodyMass, bmi, bodyFat, leanBodyMass],
            read: [height, HKCharacteristicType(.dateOfBirth), HKCharacteristicType(.biologicalSex)])
    }

    /// Height, birth year and sex from Health, where the user has granted read access.
    func profileDefaults() async -> ProfileDefaults {
        var result = ProfileDefaults()
        guard isAvailable else { return result }

        result.birthYear = (try? store.dateOfBirthComponents())?.year
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female?: result.sex = .female
        case .male?: result.sex = .male
        default: break
        }

        let latestHeight = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: height)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        if let sample = try? await latestHeight.result(for: store).first {
            result.heightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
        }
        return result
    }

    /// Saves weight (and BMI / body fat / lean mass when available). Returns the number of
    /// samples written. Types the user declined in the Health permission sheet are skipped.
    @discardableResult
    func save(_ record: MeasurementRecord) async throws -> Int {
        var samples: [HKQuantitySample] = []

        func add(_ type: HKQuantityType, _ unit: HKUnit, _ value: Double?) {
            guard let value, store.authorizationStatus(for: type) == .sharingAuthorized else { return }
            // The sync identifier makes re-saving the same weigh-in replace the sample
            // instead of duplicating it.
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: "\(record.id).\(type.identifier)",
                HKMetadataKeySyncVersion: 1,
                HKMetadataKeyWasUserEntered: false,
            ]
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                                            start: record.date, end: record.date,
                                            device: Self.device, metadata: metadata))
        }

        add(bodyMass, .gramUnit(with: .kilo), record.weightKg)
        if let c = record.composition {
            add(bmi, .count(), c.bmi)
            add(bodyFat, .percent(), c.bodyFatPercentage.map { $0 / 100 })
            add(leanBodyMass, .gramUnit(with: .kilo), c.leanBodyMassKg)
        }

        guard !samples.isEmpty else { throw SaveError.notAuthorized }
        try await store.save(samples)
        return samples.count
    }

    enum SaveError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            "Allow Scale to write Weight in Settings › Health › Data Access & Devices."
        }
    }
}
