public import LogbookModel

/// Checks a logbook against the regulations in 14 CFR Part 61.
///
/// The engine applies each rule the logbook's settings enable and the pilot's profile makes
/// relevant, and says in the report which rules it couldn't apply. A rule whose fields aren't
/// mapped is reported as not evaluated rather than passed.
///
/// ```swift
/// let engine = RegulationEngine(settings: settings)
/// let report = try await engine.evaluate(logbook.flights)
/// ```
public struct RegulationEngine: Sendable {
  /// The logbook's settings: the pilot, field mapping, aircraft and rule configuration.
  public let settings: LogbookSettings

  /// Creates an engine.
  public init(settings: LogbookSettings) {
    self.settings = settings
  }

  private static func violations(
    of rule: RegulationRule,
    in context: RegulationContext
  ) throws -> [Violation] {
    let checker = rule.checkerType.init(context: context)
    var violations = [Violation]()
    for flight in context.flights where !context.resolver.isSimulator(flight) {
      try Task.checkCancellation()
      if let violation = checker.check(flight) { violations.append(violation) }
    }
    return violations
  }

  private static func group(_ violations: [Violation], flights: [Flight]) -> [FlightViolations] {
    let rank = Dictionary(
      uniqueKeysWithValues: RegulationRule.allCases.enumerated().map { ($1, $0) }
    )
    let byFlight = Dictionary(grouping: violations, by: \.flightID)
    return flights.compactMap { flight in
      guard let found = byFlight[flight.id] else { return nil }
      return FlightViolations(
        flightID: flight.id,
        date: flight.date,
        violations: found.sorted { rank[$0.rule, default: 0] < rank[$1.rule, default: 0] }
      )
    }
  }

  /**
   Checks flights against the regulations.

   Rules run concurrently. Cancelling the task stops the check.

   - Parameters:
     - flights: Every flight in the logbook, in any order. Currency is judged from the
       whole history.
     - progress: Called with the fraction of the rules finished, from `0` to `1`.
   - Returns: The violations and what happened to each rule.
   - Throws: `CancellationError` if the task is cancelled.
   */
  public func evaluate(
    _ flights: [Flight],
    progress: ProgressTally.Report? = nil
  ) async throws -> RegulationReport {
    let statuses = Dictionary(
      uniqueKeysWithValues: RegulationRule.allCases.map { ($0, status(of: $0)) }
    )
    let context = RegulationContext(settings: settings, flights: flights)
    let rules = RegulationRule.allCases.filter { statuses[$0] == .evaluated }
    var tally = ProgressTally(total: rules.count, report: progress)
    let violations = try await withThrowingTaskGroup(of: [Violation].self) { group in
      for rule in rules { group.addTask { try Self.violations(of: rule, in: context) } }
      var violations = [Violation]()
      for try await found in group {
        violations += found
        tally.advance()
      }
      return violations
    }
    return RegulationReport(
      flights: Self.group(violations, flights: context.flights),
      statuses: statuses
    )
  }

  /// Whether a rule will be applied, and if not, why.
  public func status(of rule: RegulationRule) -> RuleStatus {
    if let reason = skipReason(for: rule) { return .skipped(reason) }
    let missing = rule.requiredRoles.filter { settings.fieldMapping[$0] == nil }
    return missing.isEmpty ? .evaluated : .notEvaluated(missingRoles: missing)
  }

  private func skipReason(for rule: RegulationRule) -> RuleSkipReason? {
    let pilot = settings.pilot
    if !settings.rules.isEnabled(rule.id) { return .disabled }
    if rule.isInstructorRule && !pilot.isFlightInstructor { return .notFlightInstructor }
    if rule.isInstructorRule && pilot.ignoresInstructionActivity {
      return .ignoresInstructionActivity
    }
    if rule == .noIFRCurrency && pilot.instrumentRatings.isEmpty { return .noInstrumentRating }
    if rule == .noFlightReview && pilot.certificateLevel == .student { return .studentPilot }
    return nil
  }
}
