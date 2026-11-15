public import Foundation
public import LogbookModel

/// A flight that appears to break a regulation.
public struct Violation: Identifiable, Hashable, Codable, Sendable {
  /// The regulation the flight appears to break.
  public let rule: RegulationRule

  /// The flight.
  public let flightID: RecordID

  /// The other flights that bear on the verdict: the ones counted toward currency, or the
  /// ones that together exceed a limit.
  public let contributingFlightIDs: [RecordID]

  /// A localized description of what is missing or exceeded, with the figures involved.
  public let explanation: String

  public var id: String { "\(rule.rawValue)/\(flightID.rawValue)" }

  /// The rule's identifier in findings and settings.
  public var ruleID: RuleID { rule.id }

  /// The regulation, such as “14 CFR 61.57(a)”.
  public var citation: String { rule.citation }

  /// The regulation's text on eCFR.
  public var citationURL: URL { rule.citationURL }

  /// The violation as an audit finding on the flight, with the contributing flights as evidence.
  public var finding: Finding {
    Finding(
      rule: rule.id,
      recordIDs: [flightID],
      message: explanation,
      evidence: [
        "contributing_flights": .array(contributingFlightIDs.map { .string($0.rawValue) })
      ],
      severity: .questionable,
      citation: citation
    )
  }

  /// Creates a violation.
  public init(
    rule: RegulationRule,
    flightID: RecordID,
    contributingFlightIDs: [RecordID] = [],
    explanation: String
  ) {
    self.rule = rule
    self.flightID = flightID
    self.contributingFlightIDs = contributingFlightIDs
    self.explanation = explanation
  }
}

/// The violations found on one flight.
public struct FlightViolations: Identifiable, Hashable, Codable, Sendable {
  /// The flight.
  public let flightID: RecordID

  /// The flight's date.
  public let date: Date

  /// The violations, in the order of `RegulationRule.allCases`.
  public let violations: [Violation]

  public var id: RecordID { flightID }
}

/// Why a rule wasn't applied to the logbook.
public enum RuleSkipReason: String, Hashable, Codable, Sendable {
  /// The rule is turned off in the logbook's settings.
  case disabled

  /// The rule concerns flight instructors and the pilot isn't one.
  case notFlightInstructor = "not_flight_instructor"

  /// The pilot's settings ignore instruction activity.
  case ignoresInstructionActivity = "ignores_instruction_activity"

  /// The pilot holds no instrument rating, so IFR currency doesn't apply.
  case noInstrumentRating = "no_instrument_rating"

  /// The pilot holds a student certificate, so flight review doesn't apply.
  case studentPilot = "student_pilot"
}

/// Whether a rule was applied to the logbook.
public enum RuleStatus: Hashable, Codable, Sendable {
  /// The rule ran, so flights without a violation passed it.
  case evaluated

  /// The rule doesn't apply to this pilot or was turned off.
  case skipped(RuleSkipReason)

  /// The rule couldn't run because fields it reads aren't mapped, so no flight passed it.
  case notEvaluated(missingRoles: [FieldRole])

  /// Whether flights without a violation passed the rule.
  public var isEvaluated: Bool { self == .evaluated }
}

/// The outcome of checking a logbook against the regulations.
public struct RegulationReport: Hashable, Codable, Sendable {
  /// The flights with violations, oldest first.
  public let flights: [FlightViolations]

  /// What happened to each rule.
  public let statuses: [RegulationRule: RuleStatus]

  /// Every violation, oldest flight first.
  public var violations: [Violation] { flights.flatMap(\.violations) }

  /// The rules that couldn't run for lack of mapped fields.
  public var unevaluatedRules: [RegulationRule] {
    RegulationRule.allCases.filter {
      if case .notEvaluated = statuses[$0] { true } else { false }
    }
  }

  /// The violations of one rule, oldest flight first.
  public func violations(of rule: RegulationRule) -> [Violation] {
    violations.filter { $0.rule == rule }
  }

  /// The violations on one flight.
  public func violations(on flightID: RecordID) -> [Violation] {
    flights.first { $0.flightID == flightID }?.violations ?? []
  }
}
