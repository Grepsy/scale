import Foundation
import MiScaleKit
import WatchKit
import WidgetKit

struct UserProfile: Codable, Equatable {
    var heightCm: Double = 170
    var birthYear: Int = 1990
    var sex: BodyComposition.Sex = .male
    /// False until imported from Health or edited, so we don't write guessed BMI/body fat.
    var isSet = false

    var age: Int { max(Calendar.current.component(.year, from: Date()) - birthYear, 6) }
}

struct AppSettings: Codable, Equatable {
    var autoSaveToHealth = true
    var usePounds = Locale.current.measurementSystem == .us
    /// The scale we first measured with. Other scales in Bluetooth range are ignored.
    var pairedScaleID: UUID?
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case waiting
        case measuring(weightKg: Double)
        case analyzing(weightKg: Double)
        case done(MeasurementRecord)
    }

    enum HealthStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    @Published private(set) var phase: Phase = .waiting
    @Published private(set) var healthStatus: HealthStatus = .idle
    @Published private(set) var history: [MeasurementRecord]
    @Published var profile: UserProfile { didSet { Self.persist(profile, key: Keys.profile) } }
    @Published var settings: AppSettings {
        didSet {
            Self.persist(settings, key: Keys.settings)
            if settings.usePounds != oldValue.usePounds { refreshWidget() }
        }
    }

    let scanner = ScaleScanner()
    private let health = HealthKitManager()
    private var tracker = MeasurementTracker()

    private enum Keys {
        static let profile = "profile"
        static let settings = "settings"
        static let history = "history"
    }

    private static let historyLimit = 60

    init() {
        profile = Self.load(Keys.profile) ?? UserProfile()
        settings = Self.load(Keys.settings) ?? AppSettings()
        history = Self.load(Keys.history) ?? []
        scanner.onReading = { [weak self] reading, scaleID in
            self?.handle(reading, from: scaleID)
        }
    }

    // MARK: Lifecycle

    func activate() {
        scanner.start()
        refreshWidget()
        Task { await prepareHealth() }
    }

    func deactivate() {
        scanner.stop()
    }

    private func prepareHealth() async {
        do {
            try await health.requestAuthorization()
        } catch {
            healthStatus = .failed(error.localizedDescription)
            return
        }
        guard !profile.isSet else { return }
        let defaults = await health.profileDefaults()
        guard !profile.isSet else { return } // user edited it meanwhile
        if let h = defaults.heightCm { profile.heightCm = h.rounded() }
        if let y = defaults.birthYear { profile.birthYear = y }
        if let s = defaults.sex { profile.sex = s }
        if defaults.heightCm != nil && defaults.birthYear != nil && defaults.sex != nil {
            profile.isSet = true
        }
    }

    // MARK: Measurements

    private func handle(_ reading: ScaleReading, from scaleID: UUID) {
        if let paired = settings.pairedScaleID, paired != scaleID { return }
        guard let event = tracker.ingest(reading) else { return }

        switch event {
        case .measuring(let kg):
            phase = .measuring(weightKg: kg)
            healthStatus = .idle
        case .stabilized(let kg):
            phase = .analyzing(weightKg: kg)
        case .completed(let measurement):
            if settings.pairedScaleID == nil { settings.pairedScaleID = scaleID }
            complete(measurement)
        }
    }

    private func complete(_ m: CompletedMeasurement) {
        let composition = profile.isSet
            ? BodyComposition(weightKg: m.weightKg, heightCm: profile.heightCm, age: profile.age,
                              sex: profile.sex, impedance: m.impedance)
            : nil
        let record = MeasurementRecord(id: m.id, date: Date(), weightKg: m.weightKg, impedance: m.impedance,
                                       composition: composition)
        upsert(record)
        phase = .done(record)
        healthStatus = .idle
        WKInterfaceDevice.current().play(.success)

        if settings.autoSaveToHealth { saveToHealth(record) }
    }

    func saveToHealth(_ record: MeasurementRecord) {
        healthStatus = .saving
        Task {
            do {
                try await health.save(record)
                var saved = record
                saved.savedToHealth = true
                upsert(saved)
                if case .done(let current) = phase, current.id == record.id { phase = .done(saved) }
                healthStatus = .saved
            } catch {
                healthStatus = .failed(error.localizedDescription)
            }
        }
    }

    func delete(_ record: MeasurementRecord) {
        history.removeAll { $0.id == record.id }
        Self.persist(history, key: Keys.history)
        refreshWidget()
    }

    func forgetScale() {
        settings.pairedScaleID = nil
    }

    private func upsert(_ record: MeasurementRecord) {
        if let i = history.firstIndex(where: { $0.id == record.id }) {
            history[i] = record
        } else {
            history.insert(record, at: 0)
            if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        }
        Self.persist(history, key: Keys.history)
        refreshWidget()
    }

    // MARK: Widget

    private static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""

    /// Publishes the latest weigh-in to the Smart Stack widget.
    private func refreshWidget() {
        let snapshot = history.first.map { latest in
            WidgetSnapshot(weightKg: latest.weightKg,
                           bodyFatPercentage: latest.composition?.bodyFatPercentage,
                           date: latest.date,
                           usePounds: settings.usePounds,
                           recentWeighIns: history.prefix(14).map(\.date))
        }
        WidgetSnapshot.save(snapshot, appGroup: Self.appGroup)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Formatting

    func formatWeight(_ kg: Double) -> String {
        settings.usePounds
            ? String(format: "%.1f lb", kg / 0.45359237)
            : String(format: "%.1f kg", kg)
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
