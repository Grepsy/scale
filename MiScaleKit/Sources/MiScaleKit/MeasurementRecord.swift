import Foundation

/// A weigh-in as kept in the app's history.
public struct MeasurementRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var date: Date
    public var weightKg: Double
    public var impedance: Int?
    /// `nil` when the user profile (height/age/sex) has not been set up yet.
    public var composition: BodyComposition?
    public var savedToHealth: Bool

    public init(id: String, date: Date, weightKg: Double, impedance: Int?, composition: BodyComposition?,
                savedToHealth: Bool = false) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.impedance = impedance
        self.composition = composition
        self.savedToHealth = savedToHealth
    }
}
