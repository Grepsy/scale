import MiScaleKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.history.isEmpty {
                Text("No weigh-ins yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.history) { record in
                NavigationLink {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.formatWeight(record.weightKg))
                                .font(.title2.weight(.semibold))
                            MetricsList(record: record)
                            if !record.savedToHealth {
                                Button("Save to Health") { model.saveToHealth(record) }
                            }
                        }
                    }
                    .navigationTitle(record.date.formatted(date: .abbreviated, time: .omitted))
                } label: {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(model.formatWeight(record.weightKg))
                            if record.savedToHealth {
                                Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption2)
                            }
                        }
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { model.delete(record) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}
