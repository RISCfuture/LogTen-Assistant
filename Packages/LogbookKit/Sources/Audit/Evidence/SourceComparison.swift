public import FlightSources
import Foundation
public import LogbookModel
public import Tracks

extension RuleID {
  /// An external source's time for an event differs from the logbook's.
  public static let telemetryTime: Self = "telemetry_time"
  /// An external source's count of takeoffs or landings differs from the logbook's.
  public static let telemetryCount: Self = "telemetry_count"
  /// Repeated records from the preferred source disagree, so no value can be chosen.
  public static let telemetrySourceConflict: Self = "telemetry_source_conflict"
  /// The logbook entry has no block times although the aircraft was seen flying.
  public static let telemetryMissingTimes: Self = "telemetry_missing_times"
}

/// A value that can be compared across sources.
public enum ObservedField: Hashable, Sendable {
  /// The time of an event.
  case time(FlyStoTimeKind)

  /// The number of events.
  case count(CountKind)

  /// A count of events.
  public enum CountKind: String, Sendable {
    /// Takeoffs.
    case takeoff
    /// Landings.
    case landing
    /// Landings that ended in a full stop.
    case fullStop = "full_stop"
  }
}

/// One source's view of an ``ObservedField`` of an entry.
public struct SourceObservation: Hashable, Sendable {
  /// The source.
  public var source: EvidenceSource
  /// The observed value: an ISO 8601 time or a count; `nil` if the source doesn't know.
  public var value: JSONValue?
  /// Whether the observation may be used. An unusable observation never wins.
  public var isUsable: Bool
  /// Whether the source's own repeated records disagree. A conflicting observation from the
  /// preferred source blocks a fallback to a lower one.
  public var hasConflict: Bool
}

/// How the sources were weighed for one field of one entry.
public struct SourceChoice: Hashable, Sendable {
  /// The entry.
  public var flightID: RecordID
  /// The field.
  public var field: ObservedField
  /// The observations, in the order the sources were consulted.
  public var observations: [SourceObservation]
  /// The source whose value was compared with the logbook, if any source was usable.
  public var selected: EvidenceSource?
  /// Whether the selected value agrees with the logbook.
  public var agrees: Bool
}

/// The findings from weighing the sources, and how each field was decided.
public struct SourceComparisonResult: Hashable, Sendable {
  /// Differences between the sources and the logbook, with proposed changes where a time is
  /// to be corrected.
  public var findings: [Finding]
  /// Every field that was compared.
  public var choices: [SourceChoice]
}

/// Compares what external sources observed with what the logbook records, preferring FlySto
/// over ADS-B for each field separately, a port of cleanup-logten's `source_priority`.
///
/// FlySto parses the aircraft's own data logs, so its block-off, takeoff, landing and block-on
/// times and its counts win. ADS-B fills in takeoffs, landings and full stops where FlySto has
/// no usable value. It never supplies block times: a first or last position report isn't brakes
/// off or on. A usable FlySto value that disagrees with the logbook becomes a finding that
/// proposes the corrected time; one that agrees silences any ADS-B discrepancy.
public struct SourceComparison: Sendable {
  private static let secondsPerMinute = 60.0
  private static let roundingFactor = 100.0
  private static let timeFields: [FlyStoTimeKind] = [.out, .in, .takeoff, .landing]
  private static let countFields: [ObservedField.CountKind] = [.takeoff, .landing, .fullStop]

  private let tolerance: AuditTolerances
  private let flyStoToleranceMinutes: Double

  /**
   Creates a comparison.

   - Parameters:
     - tolerances: How far ADS-B times may differ from the logbook's.
     - flyStoToleranceMinutes: How far FlySto times may differ; FlySto's CSV exports have
       minute precision.
   */
  public init(tolerances: AuditTolerances = .init(), flyStoToleranceMinutes: Double = 1) {
    tolerance = tolerances
    self.flyStoToleranceMinutes = flyStoToleranceMinutes
  }

  /// The first usable, known value in priority order; a conflict in a higher-priority source
  /// blocks a fallback.
  private static func select(from observations: [SourceObservation]) -> SourceObservation? {
    for source in EvidenceSource.allCases {
      for observation in observations where observation.source == source {
        if observation.hasConflict { return observation }
        if observation.isUsable && observation.value != nil { return observation }
      }
    }
    return nil
  }

  private static func fieldKey(for kind: FlyStoTimeKind) -> LogTenFieldKey {
    switch kind {
      case .out: .flightActualDepartureTime
      case .takeoff: .flightTakeoffTime
      case .landing: .flightLandingTime
      case .in: .flightActualArrivalTime
      case .startup, .shutdown: preconditionFailure("The logbook has no \(kind) time")
    }
  }

  private static func iso(_ date: Date) -> String {
    date.formatted(.iso8601)
  }

  private static func parse(_ text: String) -> Date? {
    try? Date(text, strategy: .iso8601)
  }

  private static func rounded(_ value: Double) -> Double {
    (value * roundingFactor).rounded() / roundingFactor
  }

  /**
   Weighs the sources for every entry.

   - Parameters:
     - flights: The logbook entries.
     - records: The FlySto records.
     - matches: How the records were matched to entries (see ``EvidenceMatcher``).
     - segments: Track segments.
     - segmentMatches: How the segments were matched (see ``SegmentCorrelator``).
   */
  public func compare(
    flights: [Flight],
    records: [FlyStoRecord],
    matches: [EvidenceMatch],
    segments: [TrackSegment],
    segmentMatches: [SegmentMatch]
  ) -> SourceComparisonResult {
    let recordsByID = Dictionary(records.filter(\.isFlight).map { ($0.id, $0) }) { first, _ in first
    }
    let preferred = Dictionary(
      matches.filter { $0.status == .matched }.compactMap { match in
        match.flightID.flatMap { id in recordsByID[match.sourceID].map { (id, ($0, match)) } }
      }
    ) { first, _ in first }
    let segmentsByID = Dictionary(segments.map { ($0.id, $0) }) { first, _ in first }
    var segmentsByFlight = [RecordID: [TrackSegment]]()
    for match in segmentMatches where match.flightIDs.count == 1 {
      if let segment = segmentsByID[match.segmentID] {
        segmentsByFlight[match.flightIDs[0], default: []].append(segment)
      }
    }

    var findings = [Finding]()
    var choices = [SourceChoice]()
    for flight in flights {
      let subject = Subject(
        flight: flight,
        record: preferred[flight.id]?.0,
        match: preferred[flight.id]?.1,
        segments: segmentsByFlight[flight.id] ?? []
      )
      guard subject.record != nil || !subject.segments.isEmpty else { continue }
      let outcome = compare(subject)
      findings += outcome.findings
      choices += outcome.choices
    }
    return SourceComparisonResult(findings: findings, choices: choices)
  }

  private func compare(_ subject: Subject) -> (findings: [Finding], choices: [SourceChoice]) {
    var findings = [Finding]()
    var choices = [SourceChoice]()
    var knownBlockTimes = [FlyStoTimeKind: Date]()

    let fields: [ObservedField] =
      Self.timeFields.map(ObservedField.time) + Self.countFields.map(ObservedField.count)
    for field in fields {
      let observations = self.observations(of: field, in: subject)
      guard !observations.isEmpty else { continue }
      let selected = Self.select(from: observations)
      var choice = SourceChoice(
        flightID: subject.flight.id,
        field: field,
        observations: observations,
        selected: selected?.source,
        agrees: false
      )
      if let selected, selected.hasConflict, let record = subject.record {
        findings.append(conflictFinding(field, subject: subject, record: record))
      } else if let selected {
        let outcome = finding(for: field, selected: selected, subject: subject)
        if case .time(let kind) = field, selected.source == .flySto,
          let text = selected.value?.stringValue, let date = Self.parse(text),
          kind == .out || kind == .in
        {
          knownBlockTimes[kind] = date
        }
        choice.agrees = outcome.agrees
        findings += outcome.finding.map { [$0] } ?? []
      }
      choices.append(choice)
    }
    findings += missingTimesFinding(subject, knownBlockTimes: knownBlockTimes).map { [$0] } ?? []
    return (findings, choices)
  }

  private func observations(of field: ObservedField, in subject: Subject) -> [SourceObservation] {
    var result = [SourceObservation]()
    if let record = subject.record, let observation = flyStoObservation(field, record: record) {
      result.append(observation)
    }
    if !subject.segments.isEmpty, let observation = trackObservation(field, subject: subject) {
      result.append(observation)
    }
    return result
  }

  private func flyStoObservation(_ field: ObservedField, record: FlyStoRecord) -> SourceObservation?
  {
    switch field {
      case .time(let kind):
        return SourceObservation(
          source: .flySto,
          value: record.times[kind].map { .string(Self.iso($0)) },
          isUsable: record.timeIssues.isEmpty,
          hasConflict: record.conflicts.contains(.time(kind))
        )
      case .count(let kind):
        guard let countKind = FlyStoCountKind(rawValue: kind.rawValue) else { return nil }
        let value = record.counts[countKind]
        let timeKind = FlyStoTimeKind(rawValue: kind.rawValue)!
        // Zero events with a missing boundary may reflect an incomplete recording.
        let isIncomplete = value == 0 && record.times[timeKind] == nil
        return SourceObservation(
          source: .flySto,
          value: value.map { .integer(Int($0)) },
          isUsable: !isIncomplete,
          hasConflict: record.conflicts.contains(.count(countKind))
        )
    }
  }

  private func trackObservation(_ field: ObservedField, subject: Subject) -> SourceObservation? {
    let source = EvidenceSource(trackSourceName: subject.segments[0].source)
    let events = subject.events
    switch field {
      case .time(.takeoff):
        return events.first { $0.kind == .takeoff }.map {
          observation(source, .string(Self.iso($0.time)))
        }
      case .time(.landing):
        return events.last { $0.kind == .landing }.map {
          observation(source, .string(Self.iso($0.time)))
        }
      case .time:
        return nil  // A track never shows brakes off or on.
      case .count(let kind):
        let eventKind = TrackEvent.Kind(rawValue: kind.rawValue)!
        return observation(source, .integer(events.filter { $0.kind == eventKind }.count))
    }
  }

  private func observation(_ source: EvidenceSource, _ value: JSONValue) -> SourceObservation {
    SourceObservation(source: source, value: value, isUsable: true, hasConflict: false)
  }

  private func finding(
    for field: ObservedField,
    selected: SourceObservation,
    subject: Subject
  ) -> (finding: Finding?, agrees: Bool) {
    switch field {
      case .time(let kind): timeFinding(kind, selected: selected, subject: subject)
      case .count(let kind): countFinding(kind, selected: selected, subject: subject)
    }
  }

  private func loggedTime(_ kind: FlyStoTimeKind, in flight: Flight) -> Date? {
    switch kind {
      case .out: flight.events.out
      case .takeoff: flight.events.off
      case .landing: flight.events.on
      case .in: flight.events.in
      case .startup, .shutdown: nil
    }
  }

  private func timeFinding(
    _ kind: FlyStoTimeKind,
    selected: SourceObservation,
    subject: Subject
  ) -> (finding: Finding?, agrees: Bool) {
    guard let text = selected.value?.stringValue, let observed = Self.parse(text) else {
      return (nil, false)
    }
    let flight = subject.flight
    let logged = loggedTime(kind, in: flight)
    let isBlockTime = kind == .out || kind == .in
    let isFlySto = selected.source == .flySto
    // A takeoff or landing time is only compared, never added.
    if logged == nil && !isBlockTime { return (nil, false) }
    let deltaMinutes = logged.map { observed.timeIntervalSince($0) / Self.secondsPerMinute }
    let allowed = isFlySto ? flyStoToleranceMinutes : Double(tolerance.timeToleranceMinutes)
    if let deltaMinutes, abs(deltaMinutes) <= allowed { return (nil, true) }

    var evidence: [String: JSONValue] = [
      "event": .string(kind.rawValue),
      "logged": logged.map { .string(Self.iso($0)) } ?? .null,
      "estimated": .string(Self.iso(observed)),
      "delta_minutes": deltaMinutes.map { .double(Self.rounded($0)) } ?? .null
    ]
    evidence.merge(provenance(of: selected, subject: subject)) { _, new in new }
    guard isFlySto else {
      return (
        Finding(
          rule: .telemetryTime,
          recordIDs: [flight.id],
          message: String(
            localized: "Estimated \(kind.rawValue) time differs from the logbook.",
            bundle: .module
          ),
          evidence: .object(evidence)
        ), false
      )
    }
    let change = FieldChange(
      flightKey: flight.flightKey,
      recordID: flight.id,
      field: Self.fieldKey(for: kind),
      old: logged.map(FieldValue.date) ?? .null,
      new: .date(observed.nearestMinute)
    )
    return (
      Finding(
        rule: .telemetryTime,
        recordIDs: [flight.id],
        message: String(localized: "FlySto observation differs from the logbook.", bundle: .module),
        evidence: .object(evidence),
        severity: .questionable,
        corrections: [
          CorrectionOption(
            title: String(localized: "Use FlySto’s Time", bundle: .module),
            changes: [change]
          )
        ]
      ), false
    )
  }

  private func countFinding(
    _ kind: ObservedField.CountKind,
    selected: SourceObservation,
    subject: Subject
  ) -> (finding: Finding?, agrees: Bool) {
    guard case .integer(let observed)? = selected.value else { return (nil, false) }
    let flight = subject.flight
    let logged: Int
    switch kind {
      case .takeoff: logged = Int(flight.counts.takeoffs)
      case .landing: logged = Int(flight.counts.landings)
      case .fullStop: logged = Int(flight.counts.fullStops)
    }
    if observed == logged { return (nil, true) }

    var evidence: [String: JSONValue] = [
      "event": .string(kind.rawValue), "logged": .integer(logged), "observed": .integer(observed)
    ]
    let isFlySto = selected.source == .flySto
    evidence["incomplete"] = .bool(
      !isFlySto && subject.segments.contains { $0.isIncompleteAtStart || $0.isIncompleteAtEnd }
    )
    evidence.merge(provenance(of: selected, subject: subject)) { _, new in new }
    let message =
      isFlySto
      ? String(localized: "FlySto observation differs from the logbook.", bundle: .module)
      : String(
        localized:
          "Observed \(kind.rawValue) count differs from pilot logbook; attribution may explain it.",
        bundle: .module
      )
    return (
      Finding(
        rule: .telemetryCount,
        recordIDs: [flight.id],
        message: message,
        evidence: .object(evidence),
        severity: isFlySto ? .questionable : .suggestion
      ),
      false
    )
  }

  private func conflictFinding(_ field: ObservedField, subject: Subject, record: FlyStoRecord)
    -> Finding
  {
    let (event, kind): (String, String) =
      switch field {
        case .time(let time): (time.rawValue, "time")
        case .count(let count): (count.rawValue, "count")
      }
    let values: [JSONValue] = record.rows.map { row in
      switch field {
        case .time(let time): row.times[time].map { .string(Self.iso($0)) } ?? .null
        case .count(let count):
          FlyStoCountKind(rawValue: count.rawValue).flatMap { row.counts[$0] }.map {
            .integer(Int($0))
          } ?? .null
      }
    }
    return Finding(
      rule: .telemetrySourceConflict,
      recordIDs: [subject.flight.id],
      message: String(
        localized:
          "Repeated FlySto records disagree; resolve the source before choosing a correction.",
        bundle: .module
      ),
      evidence: [
        "event": .string(event), "kind": .string(kind),
        "source": .string(EvidenceSource.flySto.rawValue),
        "source_id": .string(record.id), "source_rows": .array(record.rows.map(\.json)),
        "values": .array(values)
      ],
      severity: .questionable
    )
  }

  private func missingTimesFinding(_ subject: Subject, knownBlockTimes: [FlyStoTimeKind: Date])
    -> Finding?
  {
    let events = subject.events
    guard let takeoff = events.first(where: { $0.kind == .takeoff }),
      let landing = events.last(where: { $0.kind == .landing })
    else { return nil }
    let flight = subject.flight
    let missing = [FlyStoTimeKind.out, .in].filter { loggedTime($0, in: flight) == nil }
    guard !missing.isEmpty else { return nil }
    var evidence: [String: JSONValue] = [
      "missing": .array(missing.map { .string($0.rawValue) }),
      "source": .string(EvidenceSource(trackSourceName: subject.segments[0].source).rawValue),
      "takeoff": .string(Self.iso(takeoff.time)), "landing": .string(Self.iso(landing.time)),
      "segments": .array(subject.segments.map { .string($0.id) })
    ]
    if !knownBlockTimes.isEmpty {
      guard !missing.allSatisfy({ knownBlockTimes[$0] != nil }) else { return nil }
      evidence["preferred_known_times"] = .object(
        Dictionary(
          uniqueKeysWithValues: knownBlockTimes.map {
            ($0.key.rawValue, .string(Self.iso($0.value)))
          }
        )
      )
    }
    return Finding(
      rule: .telemetryMissingTimes,
      recordIDs: [flight.id],
      message: String(
        localized: "The logbook entry has no block times, but the aircraft was observed flying.",
        bundle: .module
      ),
      evidence: .object(evidence)
    )
  }

  /// Where the compared value came from, for the evidence.
  private func provenance(of selected: SourceObservation, subject: Subject) -> [String: JSONValue] {
    var evidence: [String: JSONValue] = ["source": .string(selected.source.rawValue)]
    evidence["segments"] = .array(subject.segments.map { .string($0.id) })
    if selected.source == .flySto, let record = subject.record {
      evidence["source_id"] = .string(record.id)
      evidence["source_rows"] = .array(record.rows.map(\.json))
      evidence["precision_seconds"] = .double(record.precision)
      if let candidate = subject.match?.selected { evidence["source_match"] = candidate.json }
    }
    return evidence
  }

  private struct Subject {
    var flight: Flight
    var record: FlyStoRecord?
    var match: EvidenceMatch?
    var segments: [TrackSegment]

    var events: [TrackEvent] { segments.flatMap(\.events).sorted { $0.time < $1.time } }
  }
}

extension FlyStoRow {
  fileprivate var json: JSONValue {
    ["file": .string(file), "row": number.map { .integer($0) } ?? .null]
  }
}

extension EvidenceMatch.Candidate {
  fileprivate var json: JSONValue {
    [
      "flight_id": .string(flightID.rawValue),
      "distance_minutes": distanceMinutes.map { .double($0) } ?? .null,
      "maximum_delta_minutes": maximumDeltaMinutes.map { .double($0) } ?? .null,
      "anchors": .integer(anchors), "date_only": .bool(isDateOnly)
    ]
  }
}

extension Date {
  /// The time rounded to the nearest whole minute, the precision LogTen logs times in.
  fileprivate var nearestMinute: Date {
    Date(timeIntervalSince1970: (timeIntervalSince1970 / 60).rounded() * 60)
  }
}
