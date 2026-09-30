import MiScaleKit
import SwiftUI
import WidgetKit

@main
struct ScaleWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScaleWidget()
    }
}

struct ScaleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScaleWidget", provider: Provider()) { entry in
            ScaleWidgetView(entry: entry)
        }
        .configurationDisplayName("Scale")
        .description("Your last weigh-in. Tap to weigh yourself.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var relevance: TimelineEntryRelevance?
}

struct Provider: TimelineProvider {
    private var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: WidgetSnapshot.load(appGroup: appGroup) ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load(appGroup: appGroup)

        // Rank the widget up in the Smart Stack around the usual weigh-in time.
        guard let window = snapshot?.nextWeighInWindow(after: now) else {
            return completion(Timeline(entries: [Entry(date: now, snapshot: snapshot)], policy: .never))
        }
        var entries: [Entry] = []
        if window.start > now {
            entries.append(Entry(date: now, snapshot: snapshot, relevance: TimelineEntryRelevance(score: 0)))
        }
        let start = max(window.start, now)
        entries.append(Entry(date: start, snapshot: snapshot,
                             relevance: TimelineEntryRelevance(score: 1, duration: window.end.timeIntervalSince(start))))
        entries.append(Entry(date: window.end, snapshot: snapshot, relevance: TimelineEntryRelevance(score: 0)))
        completion(Timeline(entries: entries, policy: .after(window.end)))
    }
}

struct ScaleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "scalemass.fill")
                    .font(.caption)
                if let s = entry.snapshot {
                    Text(shortWeight(s))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6)
                }
            }
        case .accessoryInline:
            if let s = entry.snapshot {
                Label(s.formattedWeight, systemImage: "scalemass.fill")
            } else {
                Label("Weigh in", systemImage: "scalemass.fill")
            }
        case .accessoryCorner:
            Image(systemName: "scalemass.fill")
                .font(.title3)
                .widgetLabel(entry.snapshot?.formattedWeight ?? "Weigh in")
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Scale", systemImage: "scalemass.fill")
                .font(.caption2)
                .foregroundStyle(.tint)
            if let s = entry.snapshot {
                Text(s.formattedWeight)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Group {
                    if let fat = s.bodyFatPercentage {
                        Text("\(String(format: "%.1f", fat))% fat · \(relativeDay(s.date))")
                    } else {
                        Text(relativeDay(s.date))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("Tap, then step on the scale")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortWeight(_ s: WidgetSnapshot) -> String {
        String(format: "%.1f", s.usePounds ? s.weightKg / 0.45359237 : s.weightKg)
    }

    private func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
