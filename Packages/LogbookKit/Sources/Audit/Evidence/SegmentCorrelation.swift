import FlightSources
public import Foundation
public import LogbookModel
public import Tracks

extension RuleID {
  /// Recorded aircraft activity that no logbook entry explains.
  public static let unmatchedTelemetry: Self = "unmatched_telemetry"
  /// Recorded aircraft activity that several logbook entries could explain.
  public static let ambiguousCorrelation: Self = "ambiguous_correlation"
}

/// How a track segment was assigned to logbook entries.
public struct SegmentMatch: Hashable, Sendable {
  /// The segment's identifier.
  public var segmentID: String

  /// The outcome.
  public var status: Status

  /// The entries the segment is assigned to: one for a match, any number for a manual one.
  public var flightIDs: [RecordID]

  /// Every entry that fit, best first.
  public var candidates: [Candidate]

  /// Whether the segment overlaps several separate entries, so its events must be divided
  /// among them before they are compared.
  public var requiresEventAssignment: Bool

  /// The outcome of correlating a segment.
  public enum Status: String, Codable, Sendable {
    /// One entry clearly fits.
    case matched
    /// The user chose the entries.
    case manual
    /// Several entries fit, or one fits weakly.
    case ambiguous
    /// No entry fits.
    case unmatched
  }

  /// An entry that could explain the segment.
  public struct Candidate: Hashable, Sendable {
    /// The entry.
    public var flightID: RecordID
    /// How well the entry fits, from 0 to 1.
    public var score: Double
    /// How long the segment and the entry overlap, in seconds; `nil` if the entry has no block
    /// times and only its date was compared.
    public var overlapSeconds: Double?
    /// How far the segment's start is from the entry's block out, in seconds.
    public var startDeltaSeconds: Double?
    /// The shorter duration over the longer, from 0 to 1.
    public var durationRatio: Double?
    /// Whether only the date was compared.
    public var isDateOnly: Bool
  }
}

/// A user's decision about which entries a segment belongs to.
public struct CorrelationOverride: Hashable, Codable, Sendable {
  /// The segment.
  public var segmentID: String
  /// The entries it belongs to.
  public var flightIDs: [RecordID]

  /// Creates an override.
  public init(segmentID: String, flightIDs: [RecordID]) {
    self.segmentID = segmentID
    self.flightIDs = flightIDs
  }
}

/// The result of correlating segments with entries.
public struct SegmentCorrelation: Hashable, Sendable {
  /// One match per flight segment.
  public var matches: [SegmentMatch]
  /// Findings for activity that couldn't be assigned.
  public var findings: [Finding]
}

/// Scores how well recorded flight segments fit logbook entries, a port of cleanup-logten's
/// `correlate.correlate`.
///
/// An entry with block times scores up to 0.35 for how much it overlaps the segment, 0.25 for
/// how close the starts are (within an hour), and 0.2 for similar durations; an entry without
/// block times scores 0.3 if its date matches. Matching airports add 0.1 each. A segment is
/// matched when the best entry scores at least 0.65, leads the next by 0.15, and the segment
/// doesn't span several separate entries.
public struct SegmentCorrelator: Sendable {
  private static let startWindow = 3_600.0
  private static let overlapWeight = 0.35
  private static let startWeight = 0.25
  private static let durationWeight = 0.2
  private static let dateOnlyScore = 0.3
  private static let airportBonus = 0.1
  private static let minimumOverlapDenominator = 60.0
  private static let acceptanceScore = 0.65
  private static let acceptanceLead = 0.15
  private static let spanningOverlap = 300.0
  private static let scoreDecimals = 1_000.0

  private let identity: AircraftIdentity
  private let aircraft: [String: AircraftSettings]

  /// Creates a correlator.
  public init(aircraft: [String: AircraftSettings] = [:]) {
    identity = AircraftIdentity(settings: aircraft)
    self.aircraft = aircraft
  }

  /**
   Assigns flight segments to entries.

   - Parameters:
     - segments: Track segments; only those classified as flights are correlated.
     - flights: The logbook entries.
     - overrides: The user's decisions, which take precedence over scoring.
   - Throws: ``EvidenceError/unknownOverrideFlight(_:)`` if an override names an entry that
     isn't in `flights`.
   */
  public func correlate(
    _ segments: [TrackSegment],
    with flights: [Flight],
    overrides: [CorrelationOverride] = []
  ) throws -> SegmentCorrelation {
    let known = Set(flights.map(\.id))
    let chosen = Dictionary(overrides.map { ($0.segmentID, $0.flightIDs) }) { _, last in last }
    var matches = [SegmentMatch]()
    var findings = [Finding]()
    for segment in segments where segment.isFlight {
      let candidates = self.candidates(for: segment, in: flights)
      let spans = spansSeparateEntries(candidates, flights: flights)
      let match: SegmentMatch
      if let ids = chosen[segment.id] {
        if let unknown = ids.first(where: { !known.contains($0) }) {
          throw EvidenceError.unknownOverrideFlight(unknown)
        }
        match = SegmentMatch(
          segmentID: segment.id,
          status: .manual,
          flightIDs: ids,
          candidates: candidates,
          requiresEventAssignment: spans
        )
      } else {
        match = SegmentMatch(
          segmentID: segment.id,
          status: status(of: candidates, spans: spans),
          flightIDs: isClearMatch(candidates, spans: spans) ? [candidates[0].flightID] : [],
          candidates: candidates,
          requiresEventAssignment: spans
        )
      }
      matches.append(match)
      findings += self.findings(for: match, segment: segment)
    }
    return SegmentCorrelation(matches: matches, findings: findings)
  }

  private func candidates(for segment: TrackSegment, in flights: [Flight]) -> [SegmentMatch
    .Candidate]
  {
    flights.filter { identity.isSame($0.aircraft?.registration, segment.registration) }
      .compactMap { candidate(for: segment, flight: $0) }
      .sorted { (-$0.score, $0.flightID) < (-$1.score, $1.flightID) }
  }

  private func candidate(for segment: TrackSegment, flight: Flight) -> SegmentMatch.Candidate? {
    var candidate: SegmentMatch.Candidate
    if let out = flight.events.out, let `in` = flight.events.in {
      guard let timed = timedCandidate(segment: segment, flight: flight, out: out, in: `in`) else {
        return nil
      }
      candidate = timed
    } else {
      let days = [segment.start, segment.end].map { utcCalendar.startOfDay(for: $0) }
      guard days.contains(flight.utcDay) else { return nil }
      candidate = .init(
        flightID: flight.id,
        score: Self.dateOnlyScore,
        overlapSeconds: nil,
        startDeltaSeconds: nil,
        durationRatio: nil,
        isDateOnly: true
      )
    }
    candidate.score += airportScore(segment: segment, flight: flight)
    candidate.score = (candidate.score * Self.scoreDecimals).rounded() / Self.scoreDecimals
    return candidate
  }

  private func timedCandidate(
    segment: TrackSegment,
    flight: Flight,
    out: Date,
    in end: Date
  ) -> SegmentMatch.Candidate? {
    let logged = end.timeIntervalSince(out)
    let observed = segment.end.timeIntervalSince(segment.start)
    let overlap = max(0, min(end, segment.end).timeIntervalSince(max(out, segment.start)))
    let delta = abs(out.timeIntervalSince(segment.start))
    if overlap == 0 && delta > Self.startWindow { return nil }
    let denominator = max(Self.minimumOverlapDenominator, min(max(1, logged), observed))
    var score = Self.overlapWeight * min(1, overlap / denominator)
    score += Self.startWeight * max(0, 1 - delta / Self.startWindow)
    let ratio = min(max(1, logged), max(1, observed)) / max(1, logged, observed)
    score += Self.durationWeight * ratio
    return .init(
      flightID: flight.id,
      score: score,
      overlapSeconds: overlap,
      startDeltaSeconds: delta,
      durationRatio: (ratio * Self.scoreDecimals).rounded() / Self.scoreDecimals,
      isDateOnly: false
    )
  }

  private func airportScore(segment: TrackSegment, flight: Flight) -> Double {
    let departure = segment.events.first { $0.kind == .takeoff }?.airport
    let arrival = segment.events.last { $0.kind == .landing }?.airport
    let pairs: [(String?, Place?)] = [(departure, flight.from), (arrival, flight.to)]
    let agreeing = pairs.filter { airport, place in
      guard let airport, let place else { return false }
      return place.identifierKeys.contains(airportKey(airport))
    }
    return Double(agreeing.count) * Self.airportBonus
  }

  private func spansSeparateEntries(_ candidates: [SegmentMatch.Candidate], flights: [Flight])
    -> Bool
  {
    let byID = Dictionary(uniqueKeysWithValues: flights.map { ($0.id, $0) })
    let overlapping = candidates.filter { ($0.overlapSeconds ?? 0) >= Self.spanningOverlap }
      .compactMap { byID[$0.flightID] }
    return overlapping.enumerated().contains { index, first in
      overlapping[(index + 1)...].contains { second in
        guard let firstIn = first.events.in, let firstOut = first.events.out,
          let secondIn = second.events.in, let secondOut = second.events.out
        else { return false }
        return firstIn <= secondOut || secondIn <= firstOut
      }
    }
  }

  private func isClearMatch(_ candidates: [SegmentMatch.Candidate], spans: Bool) -> Bool {
    guard !spans, let best = candidates.first, best.score >= Self.acceptanceScore else {
      return false
    }
    return candidates.count == 1 || best.score - candidates[1].score >= Self.acceptanceLead
  }

  private func status(of candidates: [SegmentMatch.Candidate], spans: Bool) -> SegmentMatch.Status {
    if isClearMatch(candidates, spans: spans) { return .matched }
    return candidates.isEmpty ? .unmatched : .ambiguous
  }

  private func findings(for match: SegmentMatch, segment: TrackSegment) -> [Finding] {
    switch match.status {
      case .unmatched:
        guard aircraft[segment.registration]?.ignoresUnmatchedActivity != true else { return [] }
        return [
          Finding(
            rule: .unmatchedTelemetry,
            recordIDs: [RecordID](),
            message: String(
              localized:
                "Aircraft flight for \(segment.registration) has no clear logbook match; another pilot may have flown it.",
              bundle: .module
            ),
            evidence: ["segment_id": .string(segment.id)]
          )
        ]
      case .ambiguous:
        return [
          Finding(
            rule: .ambiguousCorrelation,
            recordIDs: match.candidates.map(\.flightID),
            message: String(localized: "Multiple or weak matches require review.", bundle: .module),
            evidence: [
              "segment_id": .string(segment.id),
              "candidates": .array(match.candidates.map(\.json))
            ]
          )
        ]
      case .matched, .manual:
        return []
    }
  }
}

extension SegmentMatch.Candidate {
  fileprivate var json: JSONValue {
    var evidence: [String: JSONValue] = [:]
    if isDateOnly {
      evidence["date_only"] = true
    } else {
      evidence["overlap_seconds"] = .double(overlapSeconds ?? 0)
      evidence["start_delta_seconds"] = .double(startDeltaSeconds ?? 0)
      evidence["duration_ratio"] = .double(durationRatio ?? 0)
    }
    return [
      "flight_id": .string(flightID.rawValue), "score": .double(score),
      "evidence": .object(evidence)
    ]
  }
}

/// An error assembling evidence.
public enum EvidenceError: Error, Equatable {
  /// A correlation override names an entry that isn't in the logbook.
  case unknownOverrideFlight(RecordID)
  /// The instruction-activity policy needs to know which person is the logbook's owner.
  case ownerNotIdentified
}

extension EvidenceError: LocalizedError {
  public var errorDescription: String? {
    switch self {
      case .unknownOverrideFlight:
        String(localized: "A correlation override names an unknown flight.", bundle: .module)
      case .ownerNotIdentified:
        String(
          localized: "The instruction-activity policy needs an identifiable logbook owner.",
          bundle: .module
        )
    }
  }

  public var failureReason: String? {
    switch self {
      case .unknownOverrideFlight(let id): id.rawValue
      case .ownerNotIdentified: nil
    }
  }

  public var recoverySuggestion: String? {
    switch self {
      case .unknownOverrideFlight: nil
      case .ownerNotIdentified:
        String(localized: "Choose the logbook owner in Logbook Settings.", bundle: .module)
    }
  }
}
