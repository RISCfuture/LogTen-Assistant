import Audit
public import LogbookModel

/// The review queues of the Audit & Fix workflow, each holding the findings of related rules.
public enum ReviewQueue: String, CaseIterable, Codable, Sendable {
  /// Entries whose own times, counts or references disagree, and checks against reference
  /// data.
  case logbookConsistency = "logbook_consistency"

  /// Entries that disagree with what FlySto or ADS-B observed of the aircraft.
  case aircraftComparisons = "aircraft_comparisons"

  /// Recorded flights that no entry accounts for, or that fit several entries.
  case unmatchedActivity = "unmatched_activity"

  /// Smart groups whose definitions don't match the requirements they track.
  case groupsAndCurrency = "groups_and_currency"

  private static let telemetryPrefix = "telemetry_"
  private static let unmatchedRules: Set<RuleID> = [.unmatchedTelemetry, .ambiguousCorrelation]
  private static let groupRules = Set(SmartGroupRule.allCases.map(\.id))

  /// The queue that holds a rule's findings.
  public init(rule: RuleID) {
    if Self.unmatchedRules.contains(rule) {
      self = .unmatchedActivity
    } else if Self.groupRules.contains(rule) {
      self = .groupsAndCurrency
    } else if rule.rawValue.hasPrefix(Self.telemetryPrefix) {
      self = .aircraftComparisons
    } else {
      self = .logbookConsistency
    }
  }
}
