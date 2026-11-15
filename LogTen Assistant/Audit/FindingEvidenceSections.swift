import Audit
import AuditWorkflow
import FlightSources
import LogbookModel
import SwiftUI
import Tracks

/// A finding's evidence, each kind in its own inspector section: the sources that recorded the
/// flight, with what each recorded and links to its FlySto logs, and the recorded track.
struct FindingEvidenceSections: View {
  let session: LogbookSession
  let finding: Finding
  let flight: Flight?

  private var choices: [SourceChoice] {
    flight.flatMap { session.auditRun?.sourceChoices[$0.id] } ?? []
  }

  private var sources: [EvidenceSource] {
    let linked: [EvidenceSource] = flyStoLinks.isEmpty ? [] : [.flySto]
    return Set(choices.flatMap(\.observations).map(\.source) + linked).sorted()
  }

  private var track: FindingTrack? {
    session.auditRun.flatMap { FindingTrack(for: finding, in: $0) }
  }

  private var flyStoLinks: [URL] {
    let record = flight.flatMap { session.auditRun?.flyStoRecord(for: $0.id) }
    let links = (record?.urls ?? []) + (session.auditRun?.followUps[finding.id]?.sources ?? [])
    return Set(links.compactMap(\.flyStoLink)).sorted { $0.absoluteString < $1.absoluteString }
  }

  private var segment: TrackSegment? { session.auditRun?.segment(for: finding) }

  var body: some View {
    if let segment {
      InspectorSection(String(localized: "Activity")) {
        ActivityDetails(segment: segment, timeZone: session.settings.pilot.homeTimeZone)
      }
      .accessibilityIdentifier("findingInspector.activity")
    }
    if !sources.isEmpty {
      InspectorSection(String(localized: "Sources")) {
        Grid(alignment: .leadingFirstTextBaseline) {
          ForEach(sources, id: \.self) { source in
            SourceRow(
              source: source,
              fields: recordedFields(by: source),
              links: source == .flySto ? flyStoLinks : []
            )
          }
        }
      }
      .accessibilityIdentifier("findingInspector.sources")
    }
    if let track {
      InspectorSection(String(localized: "Track")) {
        TrackMap(track: track)
      }
    }
  }

  /// The compared fields for which a source recorded a value.
  private func recordedFields(by source: EvidenceSource) -> [ObservedField] {
    choices.filter { choice in
      choice.observations.contains { $0.source == source && $0.value != nil }
    }
    .map(\.field)
  }
}

/// When and in which aircraft a track segment with no logbook entry was recorded, in UTC and
/// the pilot's time zone.
private struct ActivityDetails: View {
  let segment: TrackSegment
  let timeZone: TimeZone

  var body: some View {
    Grid(alignment: .leadingFirstTextBaseline) {
      GridRow {
        Text("Aircraft").foregroundStyle(.secondary)
        Text(segment.registration)
      }
      GridRow {
        Text("Date").foregroundStyle(.secondary)
        Text(LogbookFormat.date(segment.start, in: timeZone))
      }
      TimeRow(title: String(localized: "Start"), date: segment.start, timeZone: timeZone)
      TimeRow(title: String(localized: "End"), date: segment.end, timeZone: timeZone)
    }
    .accessibilityIdentifier("findingInspector.activityDetails")
  }
}

/// A time shown in UTC and in the pilot's time zone.
private struct TimeRow: View {
  let title: String
  let date: Date
  let timeZone: TimeZone

  var body: some View {
    GridRow {
      Text(title).foregroundStyle(.secondary)
      VStack(alignment: .leading) {
        Text(LogbookFormat.clockTime(date, in: .gmt) + " " + String(localized: "UTC"))
        Text(
          LogbookFormat.clockTime(date, in: timeZone) + " "
            + LogbookFormat.zoneName(timeZone, at: date)
        )
        .foregroundStyle(.secondary)
      }
      .monospacedDigit()
    }
  }
}

/// A source that recorded the flight: its name, then what it recorded and links to its logs.
private struct SourceRow: View {
  let source: EvidenceSource
  let fields: [ObservedField]
  let links: [URL]

  var body: some View {
    GridRow {
      Text(source.title)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading) {
        if !fields.isEmpty {
          Text(fields.map(\.title), format: .list(type: .and, width: .narrow))
        }
        ForEach(links, id: \.self) { link in
          Link("Open Log", destination: link)
            .accessibilityIdentifier("findingInspector.flyStoLink")
        }
      }
    }
  }
}
