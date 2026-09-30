import Foundation

/// Body-composition estimates from weight, height, age, sex and impedance.
///
/// The scale itself only measures weight and impedance; Zepp Life computes the rest on
/// the phone. These are the formulas the open-source community reverse engineered from
/// the Mi Fit / Zepp Life app (openScale, lolouk44/xiaomi_mi_scale). Expect them to track
/// Zepp Life closely but not always match it to the decimal.
public struct BodyComposition: Codable, Equatable, Sendable {
    public enum Sex: String, Codable, CaseIterable, Sendable {
        case male
        case female
    }

    public var bmi: Double
    /// kcal per day.
    public var basalMetabolicRate: Double
    /// Percent (0–100). Requires impedance.
    public var bodyFatPercentage: Double?
    public var waterPercentage: Double?
    public var boneMassKg: Double?
    public var muscleMassKg: Double?
    /// Xiaomi's unitless visceral fat rating (1–50, healthy is under ~10).
    public var visceralFat: Double?
    public var leanBodyMassKg: Double?

    public init(weightKg: Double, heightCm: Double, age: Int, sex: Sex, impedance: Int?) {
        let c = Calculator(weight: weightKg, height: heightCm, age: Double(age), sex: sex,
                           impedance: impedance.map(Double.init))
        bmi = c.bmi
        basalMetabolicRate = c.bmr
        visceralFat = impedance == nil ? nil : c.visceralFat
        if impedance != nil {
            let fat = c.fatPercentage
            bodyFatPercentage = fat
            waterPercentage = c.waterPercentage(fat: fat)
            let bone = c.boneMass
            boneMassKg = bone
            muscleMassKg = c.muscleMass(fat: fat, bone: bone)
            leanBodyMassKg = weightKg * (1 - fat / 100)
        }
    }
}

private struct Calculator {
    let weight: Double
    let height: Double
    let age: Double
    let sex: BodyComposition.Sex
    let impedance: Double?

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    var bmi: Double {
        let m = height / 100
        return clamp(weight / (m * m), 10, 90)
    }

    var lbmCoefficient: Double {
        var lbm = (height * 9.058 / 100) * (height / 100)
        lbm += weight * 0.32 + 12.226
        lbm -= (impedance ?? 0) * 0.0068
        lbm -= age * 0.0542
        return lbm
    }

    var bmr: Double {
        var bmr: Double
        switch sex {
        case .female:
            bmr = 864.6 + weight * 10.2036 - height * 0.39336 - age * 6.204
            if bmr > 2996 { bmr = 5000 }
        case .male:
            bmr = 877.8 + weight * 14.916 - height * 0.726 - age * 8.976
            if bmr > 2322 { bmr = 5000 }
        }
        return clamp(bmr, 500, 10000)
    }

    var fatPercentage: Double {
        let constant: Double
        switch sex {
        case .female: constant = age <= 49 ? 9.25 : 7.25
        case .male: constant = 0.8
        }

        var coefficient = 1.0
        if sex == .male && weight < 61 {
            coefficient = 0.98
        } else if sex == .female && weight > 60 {
            coefficient = 0.96
            if height > 160 { coefficient *= 1.03 }
        } else if sex == .female && weight < 50 {
            coefficient = 1.02
            if height > 160 { coefficient *= 1.03 }
        }

        var fat = (1 - ((lbmCoefficient - constant) * coefficient) / weight) * 100
        if fat > 63 { fat = 75 }
        return clamp(fat, 5, 75)
    }

    func waterPercentage(fat: Double) -> Double {
        var water = (100 - fat) * 0.7
        let coefficient = water <= 50 ? 1.02 : 0.98
        if water * coefficient >= 65 { water = 75 }
        return clamp(water * coefficient, 35, 75)
    }

    var boneMass: Double {
        let base = sex == .female ? 0.245691014 : 0.18016894
        var bone = (base - lbmCoefficient * 0.05158) * -1
        bone += bone > 2.2 ? 0.1 : -0.1
        if (sex == .female && bone > 5.1) || (sex == .male && bone > 5.2) { bone = 8 }
        return clamp(bone, 0.5, 8)
    }

    func muscleMass(fat: Double, bone: Double) -> Double {
        var muscle = weight - (fat * 0.01 * weight) - bone
        if (sex == .female && muscle >= 84) || (sex == .male && muscle >= 93.5) { muscle = 120 }
        return clamp(muscle, 10, 120)
    }

    var visceralFat: Double {
        let vfal: Double
        switch sex {
        case .female:
            if weight > (13 - height * 0.5) * -1 {
                let subsub = (height * 1.45 + height * 0.1158 * height) - 120
                let sub = weight * 500 / subsub
                vfal = (sub - 6) + age * 0.07
            } else {
                let sub = 0.691 + height * -0.0024 + height * -0.0024
                vfal = ((height * 0.027 - sub * weight) * -1) + age * 0.07 - age
            }
        case .male:
            if height < weight * 1.6 {
                let sub = ((height * 0.4) - (height * (height * 0.0826))) * -1
                vfal = ((weight * 305) / (sub + 48)) - 2.9 + age * 0.15
            } else {
                let sub = 0.765 + height * -0.0015
                vfal = ((height * 0.143 - weight * sub) * -1) + age * 0.15 - 5.0
            }
        }
        return clamp(vfal, 1, 50)
    }
}
