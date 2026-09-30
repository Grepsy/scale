import MiScaleKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        Form {
            Section {
                Picker("Height", selection: profileBinding(\.heightCm)) {
                    ForEach(100...220, id: \.self) { cm in
                        Text(heightLabel(cm)).tag(Double(cm))
                    }
                }
                Picker("Born", selection: profileBinding(\.birthYear)) {
                    ForEach((currentYear - 100)...(currentYear - 6), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                Picker("Sex", selection: profileBinding(\.sex)) {
                    Text("Male").tag(BodyComposition.Sex.male)
                    Text("Female").tag(BodyComposition.Sex.female)
                }
            } header: {
                Text("Profile")
            } footer: {
                Text(model.profile.isSet
                     ? "Used for BMI and body composition."
                     : "Set these to get BMI and body composition.")
            }

            Section {
                Toggle("Save automatically", isOn: $model.settings.autoSaveToHealth)
                Toggle("Show pounds", isOn: $model.settings.usePounds)
            } header: {
                Text("Health")
            }

            Section {
                if model.settings.pairedScaleID != nil {
                    Button("Forget scale", role: .destructive) { model.forgetScale() }
                } else {
                    Text("The first scale you weigh in on will be remembered.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Scale")
            }
        }
        .navigationTitle("Settings")
    }

    /// Binding into the profile that also marks it as set by the user.
    private func profileBinding<T>(_ keyPath: WritableKeyPath<UserProfile, T>) -> Binding<T> {
        Binding {
            model.profile[keyPath: keyPath]
        } set: { value in
            model.profile[keyPath: keyPath] = value
            model.profile.isSet = true
        }
    }

    private func heightLabel(_ cm: Int) -> String {
        guard model.settings.usePounds else { return "\(cm) cm" }
        let inches = Int((Double(cm) / 2.54).rounded())
        return "\(inches / 12)′ \(inches % 12)″"
    }
}
