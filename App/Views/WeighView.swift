import MiScaleKit
import SwiftUI

struct WeighView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .waiting:
                waiting
            case .measuring(let kg):
                live(kg, caption: "Measuring…", color: .secondary)
            case .analyzing(let kg):
                live(kg, caption: "Stay still, barefoot…", color: .orange)
            case .done(let record):
                ResultView(record: record)
            }
        }
        .navigationTitle("Scale")
    }

    private var waiting: some View {
        VStack(spacing: 8) {
            Image(systemName: "scalemass")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: model.scanner.state == .scanning)
            Text(statusText)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var statusText: String {
        switch model.scanner.state {
        case .scanning: return "Step on the scale"
        case .starting, .stopped: return "Starting Bluetooth…"
        case .poweredOff: return "Turn on Bluetooth"
        case .unauthorized: return "Allow Bluetooth access in Settings › Privacy"
        case .unsupported: return "Bluetooth LE isn't available"
        }
    }

    private func live(_ kg: Double, caption: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(model.formatWeight(kg))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: kg)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(color)
        }
    }
}

struct ResultView: View {
    @EnvironmentObject private var model: AppModel
    let record: MeasurementRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.formatWeight(record.weightKg))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)

                healthRow

                MetricsList(record: record)

                if !model.profile.isSet {
                    Text("Set your height, age and sex in Settings to get body composition.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if record.impedance == nil {
                    Text("Stand barefoot until the scale finishes to get body fat.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var healthRow: some View {
        switch model.healthStatus {
        case .saving:
            Label("Saving…", systemImage: "heart")
                .font(.footnote)
        case .saved:
            Label("Saved to Health", systemImage: "heart.fill")
                .font(.footnote)
                .foregroundStyle(.pink)
        case .failed(let message):
            VStack(alignment: .leading) {
                Label("Not saved", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Retry") { model.saveToHealth(record) }
            }
        case .idle:
            if record.savedToHealth {
                Label("Saved to Health", systemImage: "heart.fill")
                    .font(.footnote)
                    .foregroundStyle(.pink)
            } else {
                Button {
                    model.saveToHealth(record)
                } label: {
                    Label("Save to Health", systemImage: "heart")
                }
            }
        }
    }
}

struct MetricsList: View {
    @EnvironmentObject private var model: AppModel
    let record: MeasurementRecord

    var body: some View {
        if let c = record.composition {
            VStack(spacing: 4) {
                row("BMI", String(format: "%.1f", c.bmi))
                if let v = c.bodyFatPercentage { row("Body fat", String(format: "%.1f %%", v)) }
                if let v = c.muscleMassKg { row("Muscle", model.formatWeight(v)) }
                if let v = c.waterPercentage { row("Water", String(format: "%.1f %%", v)) }
                if let v = c.boneMassKg { row("Bone", model.formatWeight(v)) }
                if let v = c.visceralFat { row("Visceral fat", String(format: "%.0f", v)) }
                if let v = c.leanBodyMassKg { row("Lean mass", model.formatWeight(v)) }
                row("BMR", String(format: "%.0f kcal", c.basalMetabolicRate))
                if let z = record.impedance { row("Impedance", "\(z) Ω") }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.footnote)
    }
}
