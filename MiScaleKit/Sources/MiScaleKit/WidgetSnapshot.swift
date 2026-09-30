import Foundation

/// What the app shares with its Smart Stack widget through the app group.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var weightKg: Double
    public var bodyFatPercentage: Double?
    public var date: Date
    public var usePounds: Bool
    /// Recent weigh-in times, newest first, used to guess when the widget is relevant.
    public var recentWeighIns: [Date]

    public init(weightKg: Double, bodyFatPercentage: Double?, date: Date, usePounds: Bool, recentWeighIns: [Date]) {
        self.weightKg = weightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.date = date
        self.usePounds = usePounds
        self.recentWeighIns = recentWeighIns
    }

    public static let placeholder = WidgetSnapshot(weightKg: 72.4, bodyFatPercentage: 21.3, date: Date(),
                                                   usePounds: false, recentWeighIns: [])

    private static let key = "widgetSnapshot"

    public static func load(appGroup: String) -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: WidgetSnapshot?, appGroup: String) {
        let defaults = UserDefaults(suiteName: appGroup)
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults?.set(data, forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
    }

    public var formattedWeight: String {
        usePounds ? String(format: "%.1f lb", weightKg / 0.45359237) : String(format: "%.1f kg", weightKg)
    }

    /// The next 90-minute window around the user's usual weigh-in time, skipping today
    /// if they've already weighed in. `nil` until there are at least three weigh-ins.
    public func nextWeighInWindow(after now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard recentWeighIns.count >= 3 else { return nil }
        let minutes = recentWeighIns
            .map { calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) }
            .sorted()
        let usual = minutes[minutes.count / 2]
        let duration: TimeInterval = 90 * 60

        guard var start = calendar.date(byAdding: .minute, value: usual - 30, to: calendar.startOfDay(for: now))
        else { return nil }
        let weighedToday = recentWeighIns.contains { calendar.isDate($0, inSameDayAs: now) }
        if weighedToday || now >= start.addingTimeInterval(duration) {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            start = tomorrow
        }
        return DateInterval(start: start, duration: duration)
    }
}
