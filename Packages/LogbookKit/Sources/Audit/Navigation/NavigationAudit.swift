import Foundation
public import LogbookModel
public import References
import Tracks

extension RuleID {
  /// The aircraft's track supports the approaches logged.
  public static let telemetryApproachCorroboration: Self = "telemetry_approach_corroboration"
  /// The aircraft's track supports an approach but differs from the logged detail.
  public static let telemetryApproachDetail: Self = "telemetry_approach_detail"
  /// The aircraft's track forms hold candidates in logged instrument context.
  public static let telemetryHoldCandidates: Self = "telemetry_hold_candidates"
  /// The evidence can't independently show all the approaches or holds logged.
  public static let telemetryNavigationCoverage: Self = "telemetry_navigation_coverage"
}

/// The findings of a navigation audit and what helps a reviewer decide them.
public struct NavigationAuditResult: Hashable, Sendable {
  /// The findings.
  public var findings: [Finding]
  /// The follow-up of each finding.
  public var followUps: [FindingID: AuditFollowUp]
}

/**
 Compares the approaches and holds an entry logs with what the aircraft's track shows, a port of
 the navigation half of cleanup-logten's `activity_audit`.

 Approaches are named by matching the track to published procedures; holds are candidates from
 track geometry in logged instrument context. The track shows where the aircraft went, not
 whether it was in cloud, who flew it, or whether the maneuver was completed, so every finding
 is a candidate for review and none proposes a change. Entries flown as instruction are not
 compared.
 */
public struct NavigationAudit: Sendable {
  private typealias Item = (finding: Finding, followUp: AuditFollowUp)

  private let detector: ApproachDetector?
  private let holds: HoldDetector

  /**
   Creates an audit.

   - Parameters:
     - index: Airport positions; without them, and without a lookup, approaches aren't named.
     - lookup: The published approaches.
     - holdThresholds: What counts as a hold.
   */
  public init(
    index: AirportIndex? = nil,
    lookup: (any ApproachLookup)? = nil,
    holdThresholds: HoldDetector.Thresholds = .init()
  ) {
    if let index, let lookup {
      detector = ApproachDetector(index: index, lookup: lookup)
    } else {
      detector = nil
    }
    holds = HoldDetector(thresholds: holdThresholds)
  }

  private static func family(of type: ApproachType?) -> ApproachFamily? {
    let name = type?.rawValue.uppercased() ?? ""
    if name.contains("ILS") { return .ils }
    if ["LOC", "LDA", "IGS"].contains(where: name.contains) { return .localizer }
    if ["RNAV", "GPS", "LPV", "LNAV", "GLS"].contains(where: name.contains) { return .rnav }
    return nil
  }

  /// The runway number and designator, such as `09L`, from text like `RWY 9L`.
  private static func runway(_ text: String?) -> String? {
    let upper = text?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
    guard let match = upper.wholeMatch(of: /(?:RWY?\s*)?(0?[1-9]|[12][0-9]|3[0-6])([LRC]?)/) else {
      return nil
    }
    return String(match.1).leftPadded(to: 2) + match.2
  }

  private static func json(of approach: Approach) -> JSONValue {
    [
      "type": approach.type.map { .string($0.rawValue) } ?? .null,
      "airport": approach.place.map { .string($0.preferredIdentifier) } ?? .null,
      "runway": approach.runway.map(JSONValue.string) ?? .null,
      "quantity": .integer(Int(approach.count))
    ]
  }

  /**
   Audits the entries that have external evidence.

   - Parameters:
     - flights: The logbook entries.
     - contexts: The evidence for each entry.
   */
  public func run(on flights: [Flight], contexts: [RecordID: EvidenceContext]) async
    -> NavigationAuditResult
  {
    var result = NavigationAuditResult(findings: [], followUps: [:])
    for flight in flights {
      guard let context = contexts[flight.id], !context.isInstruction else { continue }
      for item in await findings(for: flight, context) {
        result.findings.append(item.finding)
        result.followUps[item.finding.id] = item.followUp
      }
    }
    return result
  }

  private func findings(for flight: Flight, _ context: EvidenceContext) async -> [Item] {
    let positions = context.usablePositions
    let episodes = await detector?.episodes(in: context, positions: positions) ?? []
    let isInstrument =
      flight.times.actualInstrument > 0 || flight.times.simulatedInstrument > 0
      || flight.isSimulatorEntry
    let found = isInstrument ? holds.candidates(in: positions) : []
    let logged = flight.approaches.filter { $0.count >= 1 }
    var items = [Item]()
    if !episodes.isEmpty {
      items.append(approachItem(flight, context, episodes, logged))
    }
    if !found.isEmpty {
      items.append(holdItem(flight, context, found))
    }
    let hasLoggedHolds = flight.counts.holds > 0
    if (!logged.isEmpty || hasLoggedHolds)
      && (episodes.isEmpty || (hasLoggedHolds && found.isEmpty))
    {
      items.append(coverageItem(flight, context, positions, episodes, found, logged))
    }
    return items
  }

  // MARK: Approaches

  /// Compares the detail of the one logged approach with the one episode; with more of either,
  /// no episode could be assigned to a particular approach.
  private func compare(_ logged: [Approach], _ episodes: [ApproachEpisode]) -> Comparison {
    var comparison = Comparison()
    guard logged.count == 1, episodes.count == 1, logged[0].count == 1 else { return comparison }
    let approach = logged[0]
    let episode = episodes[0]
    let details: [(String, String?, String?)] = [
      ("type", Self.family(of: approach.type)?.rawValue, episode.family?.rawValue),
      (
        "airport", approach.place.map { $0.preferredIdentifier.uppercased() },
        episode.airport.uppercased()
      ),
      ("runway", Self.runway(approach.runway), episode.runway)
    ]
    for (field, loggedValue, observed) in details {
      guard let loggedValue, let observed else { continue }
      let entry: JSONValue = [
        "field": .string(field),
        "logged": .string(loggedValue),
        "observed": .string(observed)
      ]
      if loggedValue == observed {
        comparison.agreements.append(entry)
      } else {
        comparison.contradictions.append(entry)
      }
    }
    return comparison
  }

  private func approachItem(
    _ flight: Flight,
    _ context: EvidenceContext,
    _ episodes: [ApproachEpisode],
    _ logged: [Approach]
  ) -> Item {
    let comparison = compare(logged, episodes)
    let rule: RuleID =
      comparison.contradictions.isEmpty ? .telemetryApproachCorroboration : .telemetryApproachDetail
    var evidence = baseEvidence(context)
    evidence["observed"] = .array(episodes.map(\.jsonValue))
    evidence["logged"] = .array(logged.map(Self.json(of:)))
    evidence["contradictions"] = .array(comparison.contradictions)
    evidence["agreements"] = .array(comparison.agreements)
    return item(
      flight,
      context,
      rule: rule,
      message: String(
        localized:
          "Matched published approach fixes support approach candidates; verify logged detail and pilot credit.",
        bundle: .module
      ),
      evidence: evidence,
      events: episodes.map { TrackEvent(kind: .landing, time: $0.end) },
      notes: [
        String(
          localized:
            "Passing the published fixes of an approach shows where the aircraft flew; it does not establish IMC, execution, completion or pilot credit.",
          bundle: .module
        ),
        String(
          localized:
            "Approach detail comparison requires a unique logged approach and observed episode; unknown airport, runway or type remains unknown.",
          bundle: .module
        )
      ]
    )
  }

  // MARK: Holds

  private func holdItem(_ flight: Flight, _ context: EvidenceContext, _ found: [HoldCandidate])
    -> Item
  {
    var evidence = baseEvidence(context)
    evidence["observed"] = .array(found.map(\.jsonValue))
    evidence["logged"] = ["holds": .integer(Int(flight.counts.holds))]
    evidence["instrument_context"] = [
      "actualinstrument": .integer(Int(flight.times.actualInstrument)),
      "simulatedinstrument": .integer(Int(flight.times.simulatedInstrument))
    ]
    return item(
      flight,
      context,
      rule: .telemetryHoldCandidates,
      message: String(
        localized:
          "Repeated reciprocal track legs form hold candidates in logged instrument context; confirm the procedure and pilot credit.",
        bundle: .module
      ),
      evidence: evidence,
      events: found.map { TrackEvent(kind: .gap, time: $0.start) },
      notes: [
        String(
          localized:
            "Repeated reciprocal straight legs, spatial recurrence, altitude stability and continuous coverage support a racetrack candidate; they do not prove an instrument hold.",
          bundle: .module
        ),
        String(
          localized:
            "Logged instrument time supplies context, not proof that the maneuver occurred in IMC or qualified for credit.",
          bundle: .module
        ),
        String(
          localized:
            "Aircraft tracking can resemble maneuvering or loiter; no exact hold count or correction is inferred.",
          bundle: .module
        )
      ]
    )
  }

  // MARK: Coverage

  private func coverageItem(
    _ flight: Flight,
    _ context: EvidenceContext,
    _ positions: [TrackSample],
    _ episodes: [ApproachEpisode],
    _ found: [HoldCandidate],
    _ logged: [Approach]
  ) -> Item {
    var evidence = baseEvidence(context)
    evidence["observed"] = [
      "samples": .integer(positions.count),
      "approach_episodes": .integer(episodes.count),
      "hold_candidates": .integer(found.count)
    ]
    evidence["logged"] = [
      "approaches": .array(logged.map(Self.json(of:))),
      "holds": .integer(Int(flight.counts.holds))
    ]
    return item(
      flight,
      context,
      rule: .telemetryNavigationCoverage,
      message: String(
        localized:
          "Available navigation evidence cannot independently corroborate all logged approaches or holds.",
        bundle: .module
      ),
      evidence: evidence,
      events: [],
      notes: [
        String(
          localized:
            "Absent matches and track gaps do not establish that an approach or hold did not occur.",
          bundle: .module
        ),
        String(
          localized:
            "No IMC, hood use, pilot identity, completion or personal credit is inferred from navigation or aircraft movement.",
          bundle: .module
        )
      ]
    )
  }

  // MARK: Findings

  private func baseEvidence(_ context: EvidenceContext) -> [String: JSONValue] {
    [
      "source": context.positionSource.map { .string($0.rawValue) } ?? .null,
      "segments": .array(context.segments.map { .string($0.id) })
    ]
  }

  private func item(
    _ flight: Flight,
    _ context: EvidenceContext,
    rule: RuleID,
    message: String,
    evidence: [String: JSONValue],
    events: [TrackEvent],
    notes: [String]
  ) -> Item {
    (
      Finding(
        rule: rule,
        recordIDs: [flight.id],
        message: message,
        evidence: .object(evidence)
      ),
      AuditFollowUp(notes: notes, events: events, sources: context.urls)
    )
  }

  private struct Comparison {
    var agreements = [JSONValue]()
    var contradictions = [JSONValue]()
  }
}

extension String {
  /// The text with leading zeros so it is at least `width` characters long.
  fileprivate func leftPadded(to width: Int) -> String {
    String(repeating: "0", count: max(0, width - count)) + self
  }
}
