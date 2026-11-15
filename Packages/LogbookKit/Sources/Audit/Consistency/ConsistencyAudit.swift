public import Foundation
public import LogbookModel

/**
 Checks a logbook for internal inconsistencies: counts and times that exceed what contains
 them, out-of-order or implausible times, duplicate entries and records, overlapping flights,
 missing IFR capability, the logbook's custom rules, and custom times beyond total time.

 The rules are ports of cleanup-logten's `audit.py` and `expanded_audit.py`, and produce the
 same rule identifiers and evidence keys, so a finding's identifier matches cleanup's for the
 same data wherever the stored values are the same. The other rules cover the checks of
 LogTen's Flight Audit. Each rule is implemented by a ``ConsistencyCheck`` listed in
 ``ConsistencyCheckRegistry``; a check runs only when one of its rules is enabled in the
 logbook's `RuleSettings`, and disabled rules produce no findings.

 ```swift
 let result = ConsistencyAudit(settings: settings).run(on: logbook)
 for finding in result.findings where finding.severity == .discrepancy { … }
 ```
 */
public struct ConsistencyAudit: Sendable {
  /// The logbook's settings: field mapping, aircraft, custom rules and tolerances.
  public var settings: LogbookSettings

  /// Options that aren't part of the logbook settings.
  public var options: ConsistencyAuditOptions

  /// Creates an audit.
  public init(settings: LogbookSettings, options: ConsistencyAuditOptions = .init()) {
    self.settings = settings
    self.options = options
  }

  /**
   Runs every enabled consistency rule over a logbook.

   - Parameters:
     - logbook: A logbook snapshot.
     - date: The date the audit is run as of, which decides what is in the future.
   - Returns: The findings, ordered by rule and identifier, with their analyses.
   */
  public func run(on logbook: Logbook, asOf date: Date = .now) -> ConsistencyAuditResult {
    let rules = settings.rules
    let context = ConsistencyContext(
      logbook: logbook,
      settings: settings,
      options: options,
      asOf: date
    )
    var collector = FindingCollector()
    for check in ConsistencyCheckRegistry.checks
    where check.rules.contains(where: { $0.isEnabled(in: rules) }) {
      check.check(context, into: &collector)
    }
    CustomRuleChecks(rules: rules.customRules, logbook: logbook)
      .check(context.flights, into: &collector)
    return collector.result(enabling: rules.runs)
  }
}

/// Consistency-audit options that the logbook settings don't hold.
public struct ConsistencyAuditOptions: Hashable, Codable, Sendable {
  /// Custom time fields that must never exceed total time, each checked on its own.
  ///
  /// Only fields known to hold part of the flight belong here: a custom time such as duty
  /// time may legitimately exceed total time.
  public var boundedCustomTimeFields: [LogTenFieldKey]

  /// Creates options.
  public init(boundedCustomTimeFields: [LogTenFieldKey] = []) {
    self.boundedCustomTimeFields = boundedCustomTimeFields
  }
}

/// The findings of a consistency audit.
public struct ConsistencyAuditResult: Hashable, Codable, Sendable {
  /// The findings, ordered by rule and then identifier.
  public var findings: [Finding]

  /// Explanations for some of the findings, by finding.
  public var analyses: [FindingID: FindingAnalysis]

  /// Creates a result.
  public init(findings: [Finding], analyses: [FindingID: FindingAnalysis] = [:]) {
    self.findings = findings
    self.analyses = analyses
  }
}

extension Logbook {
  /// The title LogTen shows for a field: the custom title for a custom slot, otherwise the
  /// built-in title, otherwise the attribute name.
  func title(of key: LogTenFieldKey) -> String {
    customField(for: key)?.title
      ?? FieldTitle.title(ofAttribute: key.attributeName.lowercased())
      ?? String(key.attributeName)
  }
}
