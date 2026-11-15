import Foundation
public import LogbookModel
public import LogbookStore

/**
 Evaluates a logbook's smart groups and checks their definitions against the currency
 requirements they appear to track.

 Groups with a predicate are evaluated with `NSPredicate` against the snapshot, as LogTen
 evaluates them. Groups defined only by criteria are reported but not evaluated, since how
 LogTen combines criteria with child groups and date windows isn't established. The
 definition checks inspect a group's criteria and predicate, not its name: a group may
 deliberately implement only part of a requirement, so every finding is a prompt to review.
 */
public struct SmartGroupAudit: Sendable {
  private static let citation61_56 = "14 CFR 61.56"
  private static let citation61_57 = "14 CFR 61.57"
  private static let citation61_58 = "14 CFR 61.58"
  private static let approachesKey = "flight_totalInstrumentApproaches"
  private static let nightLandingsKey = "flight_nightLandings"
  private static let landingKeys: Set = ["flight_totalLandings", nightLandingsKey]
  private static let reviewKey = "flight_review"
  private static let noteKeyFragment = "customNote"
  private static let yearInMonths = 12
  private static let dayIncrement = 1

  /// The logbook's field mapping, which names the night-full-stop, tracking and
  /// proficiency-check fields.
  public var mapping: FieldMapping

  /// Rules the user has turned off.
  public var disabledRules: Set<RuleID>

  private var landingKeys: Set<String> {
    Self.landingKeys.union([mapping[.nightFullStops]?.rawValue].compactMap(\.self))
  }

  /// Creates a smart-group audit.
  public init(mapping: FieldMapping, disabledRules: Set<RuleID> = []) {
    self.mapping = mapping
    self.disabledRules = disabledRules
  }

  /**
   Evaluates every group and checks every smart group's definition.

   - Parameters:
     - groups: The logbook's groups.
     - resolver: Evaluates group membership, normally the snapshot's `LogbookReader`.
     - windows: Each group's rolling date window, where known; checks that depend on a window
       are skipped for groups without one.
   - Returns: The evaluations, in group order, and the findings.
   */
  public func run(
    on groups: [LogbookGroup],
    resolver: some GroupMembershipResolving,
    windows: [RecordID: SmartGroupWindow] = [:]
  ) async -> SmartGroupAuditResult {
    var evaluations = [SmartGroupEvaluation]()
    var collector = FindingCollector()
    for group in groups {
      evaluations.append(await evaluate(group, resolver: resolver))
      checkDefinition(of: group, window: windows[group.id], into: &collector)
    }
    let findings = collector.result { !disabledRules.contains($0) }.findings
    return SmartGroupAuditResult(evaluations: evaluations, findings: findings)
  }

  private func evaluate(
    _ group: LogbookGroup,
    resolver: some GroupMembershipResolving
  ) async -> SmartGroupEvaluation {
    let status: SmartGroupEvaluation.Status
    if group.predicateFormat != nil || !group.isSmart {
      do {
        status = .evaluated(try await resolver.flightIDs(in: group))
      } catch {
        status = .failed(reason: error.localizedDescription)
      }
    } else {
      status = .criteriaNotEvaluated
    }
    return SmartGroupEvaluation(group: group, status: status)
  }

  // MARK: - Definition checks

  private func checkDefinition(
    of group: LogbookGroup,
    window: SmartGroupWindow?,
    into collector: inout FindingCollector
  ) {
    let keys = Set(group.criteria.compactMap(\.searchKey))
    if keys.contains(Self.approachesKey) {
      checkInstrumentGroup(group, keys: keys, window: window, into: &collector)
    }
    if !keys.isDisjoint(with: landingKeys), let window,
      let increment = window.increment, increment != Self.dayIncrement
    {
      emit(
        .passengerWindow,
        group,
        message: String(
          localized: "Passenger recency uses 90 days; this group uses another date increment.",
          bundle: .module
        ),
        evidence: [
          "value": window.value.map(JSONValue.integer) ?? .null, "increment": .integer(increment)
        ],
        citation: Self.citation61_57,
        into: &collector
      )
    }
    if keys.contains(Self.nightLandingsKey),
      !keys.contains(mapping[.nightFullStops]?.rawValue ?? "")
    {
      emit(
        .nightFullStops,
        group,
        message: String(
          localized: "Night landings alone don’t establish the full-stop requirement.",
          bundle: .module
        ),
        citation: Self.citation61_57,
        into: &collector
      )
    }
    if group.predicateFormat?.contains(Self.reviewKey) == true,
      !keys.contains(where: { $0.contains(Self.noteKeyFragment) })
    {
      emit(
        .reviewAlternatives,
        group,
        message: String(
          localized:
            "This flight-review group may omit qualifying practical tests, proficiency checks or WINGS phases.",
          bundle: .module
        ),
        citation: Self.citation61_56,
        into: &collector
      )
    }
    if let proficiencyKey = mapping[.proficiencyCheck], keys.contains(proficiencyKey.rawValue),
      window?.value == Self.yearInMonths
    {
      emit(
        .proficiencyCheckWindows,
        group,
        message: String(
          localized:
            "Review the annual qualifying check and the 24-month type-specific check separately, including credited due months.",
          bundle: .module
        ),
        citation: Self.citation61_58,
        into: &collector
      )
    }
  }

  private func checkInstrumentGroup(
    _ group: LogbookGroup,
    keys: Set<String>,
    window: SmartGroupWindow?,
    into collector: inout FindingCollector
  ) {
    if !keys.contains(mapping[.interceptingAndTracking]?.rawValue ?? "") {
      emit(
        .instrumentTracking,
        group,
        message: String(
          localized:
            "This approach and hold group doesn’t test intercepting and tracking; check the complete currency hierarchy.",
          bundle: .module
        ),
        evidence: ["keys": .array(keys.sorted().map(JSONValue.string))],
        citation: Self.citation61_57,
        into: &collector
      )
    }
    if window?.value == Self.yearInMonths {
      emit(
        .instrumentRecovery,
        group,
        message: String(
          localized:
            "A 12-month instrument group is a recovery aid, not proof of current IFR privileges.",
          bundle: .module
        ),
        citation: Self.citation61_57,
        into: &collector
      )
    }
  }

  private func emit(
    _ rule: SmartGroupRule,
    _ group: LogbookGroup,
    message: String,
    evidence: [String: JSONValue] = [:],
    citation: String,
    into collector: inout FindingCollector
  ) {
    collector.emit(
      rule.id,
      [group.id],
      message: message,
      evidence: .object(evidence.merging(["group": .string(group.name)]) { $1 }),
      severity: .questionable,
      citation: citation
    )
  }
}

/// Something that can list the flights in a logbook group.
public protocol GroupMembershipResolving: Sendable {
  /// The identifiers of the flights in a group.
  func flightIDs(in group: LogbookGroup) async throws -> [RecordID]
}

extension LogbookReader: GroupMembershipResolving {}

/// A smart group's rolling date window, as LogTen stores it (`group_dateValue` and
/// `group_dynamicDateIncrement`).
public struct SmartGroupWindow: Hashable, Codable, Sendable {
  /// How many increments the window spans, such as 90 or 12.
  public var value: Int?

  /// LogTen's code for the increment's unit; `1` is days.
  public var increment: Int?

  /// Creates a window.
  public init(value: Int?, increment: Int?) {
    self.value = value
    self.increment = increment
  }
}

/// The result of a smart-group audit.
public struct SmartGroupAuditResult: Hashable, Codable, Sendable {
  /// Each group's evaluation, in group order.
  public var evaluations: [SmartGroupEvaluation]

  /// Findings about group definitions, ordered by rule and identifier.
  public var findings: [Finding]

  /// Creates a result.
  public init(evaluations: [SmartGroupEvaluation], findings: [Finding]) {
    self.evaluations = evaluations
    self.findings = findings
  }
}

/// How one group's membership was determined.
public struct SmartGroupEvaluation: Hashable, Codable, Sendable {
  /// The group.
  public var group: LogbookGroup

  /// Whether, and with what result, the group was evaluated.
  public var status: Status

  /// Creates an evaluation.
  public init(group: LogbookGroup, status: Status) {
    self.group = group
    self.status = status
  }

  /// The outcome of evaluating a group.
  public enum Status: Hashable, Codable, Sendable {
    /// The group's predicate, or its assigned members for a plain group, gave these flights.
    case evaluated([RecordID])
    /// The group is defined only by criteria, which aren't evaluated.
    case criteriaNotEvaluated
    /// The group's predicate couldn't be evaluated.
    case failed(reason: String)
  }
}
