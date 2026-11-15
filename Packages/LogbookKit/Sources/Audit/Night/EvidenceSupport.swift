public import Foundation
import LogbookModel
public import Tracks

/// What a reviewer needs beside a finding drawn from external evidence: why it is only a
/// candidate, the events behind it and where to look.
///
/// Follow-ups are not part of a finding's evidence, so they don't affect its identifier.
public struct AuditFollowUp: Hashable, Codable, Sendable {
  /// A short statement of what to review, when it adds to the finding's message.
  public var summary: String?

  /// Cautions about what the evidence does and doesn't establish.
  public var notes: [String]

  /// The track events behind the finding.
  public var events: [TrackEvent]

  /// Links to the source records, such as the flight on flysto.net.
  public var sources: [URL]

  /// Creates a follow-up.
  public init(
    summary: String? = nil,
    notes: [String] = [],
    events: [TrackEvent] = [],
    sources: [URL] = []
  ) {
    self.summary = summary
    self.notes = notes
    self.events = events
    self.sources = sources
  }
}

extension EvidenceContext {
  /// The positions to measure with: the full ADS-B track within the logged block times if there
  /// is one, otherwise the segments' track, without positions judged impossible.
  var usablePositions: [TrackSample] {
    let candidates = adsbPoints.isEmpty ? points : adsbPoints
    let usable = candidates.filter { !$0.isPositionOutlier }
    return usable.map(\.sample).sorted { $0.time < $1.time }
  }

  /// The evidence fields every telemetry finding carries, naming where the data came from.
  var provenanceEvidence: [String: JSONValue] {
    [
      "source": positionSource.map { .string($0.rawValue) } ?? .null,
      "preferred_source": .string(primarySource.rawValue),
      "source_ids": .array(sourceIDs.map(JSONValue.string)),
      "segments": .array(segments.map { .string($0.id) })
    ]
  }

  /// The events inside the entry's interval, in time order.
  var eventsWithinInterval: [TrackEvent] {
    events.filter { event in
      (start.map { event.time >= $0 } ?? true) && (end.map { event.time <= $0 } ?? true)
    }
  }
}

extension TrackSample {
  /// Whether the sample's latitude and longitude are on the globe.
  var hasValidPosition: Bool {
    (-90...90).contains(latitudeDeg) && (-180...180).contains(longitudeDeg)
  }
}

extension TrackEvent {
  /// The event's position if it has a valid one.
  var validPosition: (latitudeDeg: Double, longitudeDeg: Double)? {
    guard let latitudeDeg, let longitudeDeg, (-90...90).contains(latitudeDeg),
      (-180...180).contains(longitudeDeg)
    else { return nil }
    return (latitudeDeg, longitudeDeg)
  }
}

extension Flight {
  /// Whether the entry was flown in a simulator or training device rather than an aircraft.
  var isSimulatorEntry: Bool {
    times.simulator > 0 || aircraft?.type?.category?.isSimulationDevice == true
  }
}
