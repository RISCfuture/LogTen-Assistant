import Foundation
import LogbookModel

/// Explains a disagreement between a flight's out-to-in interval and its logged total time by
/// enumerating day-offset and swapped-time alternatives, without choosing one.
struct TimeDiagnosis {
  private static let dayShifts = -2...2
  private static let minutesPerDay: UInt = 1440
  private static let minutesPerHour = 60.0
  private static let secondsPerDay = 86_400.0
  private static var partialCreditPattern: Regex<Substring> {
    /\bsafety pilot\b|\bpartial (?:flight|credit)\b/.ignoresCase()
  }

  let toleranceMinutes: UInt
  let maximumMinutes: UInt

  /// The analysis of a flight's times, or `nil` if it lacks out or in times or total time.
  func analysis(of flight: AuditedFlight) -> FindingAnalysis? {
    let total = flight.flight.times.total
    guard let start = flight.flight.events.out, let end = flight.flight.events.in, total > 0 else {
      return nil
    }
    let elapsed = PythonTimestamp.minutes(from: start, to: end)
    var analysis = FindingAnalysis()
    analysis.isPartialCredit = isPartialCredit(flight, total: total, elapsed: elapsed)
    if analysis.isPartialCredit {
      analysis.summary = String(
        localized:
          "The remarks describe partial-flight credit. The aircraft’s elapsed time need not equal the time this pilot logged; confirm attribution before changing either.",
        bundle: .module
      )
    }
    if agrees(elapsed: elapsed, total: total) { return analysis }

    let target = total > maximumMinutes ? total % Self.minutesPerDay : total
    guard target > 0 else { return analysis }
    let candidates = cheapest(candidates(start: start, end: end, target: Double(target)))
    if !candidates.isEmpty {
      analysis.dateErrorCandidates = candidates
      analysis.summary = candidateSummary(totalContainsWholeDays: total > maximumMinutes)
    } else if isNearWholeHours(elapsed: elapsed, total: total) {
      analysis.summary = String(
        localized:
          "The discrepancy is close to a whole number of hours. A time-zone entry error is possible, but which time is wrong isn’t established.",
        bundle: .module
      )
    }
    return analysis
  }

  private func isPartialCredit(_ flight: AuditedFlight, total: UInt, elapsed: Double) -> Bool {
    guard let remarks = flight.flight.remarks, remarks.contains(Self.partialCreditPattern) else {
      return false
    }
    return Double(total) < elapsed && elapsed <= Double(maximumMinutes)
  }

  private func agrees(elapsed: Double, total: UInt) -> Bool {
    abs(elapsed - Double(total)) <= Double(toleranceMinutes) && elapsed <= Double(maximumMinutes)
  }

  private func candidates(start: Date, end: Date, target: Double) -> [DateErrorCandidate] {
    var candidates = [DateErrorCandidate]()
    for swapped in [false, true] {
      let (first, second) = swapped ? (end, start) : (start, end)
      for outShift in Self.dayShifts {
        for inShift in Self.dayShifts where swapped || outShift != inShift {
          let out = first.addingTimeInterval(Double(outShift) * Self.secondsPerDay)
          let `in` = second.addingTimeInterval(Double(inShift) * Self.secondsPerDay)
          let minutes = PythonTimestamp.minutes(from: out, to: `in`)
          guard minutes > 0, minutes <= Double(maximumMinutes),
            abs(minutes - target) <= Double(toleranceMinutes)
          else { continue }
          candidates.append(
            DateErrorCandidate(
              out: out,
              in: `in`,
              minutes: (minutes * 100).rounded() / 100,
              swapsOutAndIn: swapped,
              outDayShift: outShift,
              inDayShift: inShift
            )
          )
        }
      }
    }
    return candidates
  }

  private func cheapest(_ candidates: [DateErrorCandidate]) -> [DateErrorCandidate] {
    guard let cost = candidates.map(\.cost).min() else { return [] }
    return candidates.filter { $0.cost == cost }
  }

  private func candidateSummary(totalContainsWholeDays: Bool) -> String {
    let summary = String(
      localized:
        "Day-offset or swapped-time alternatives fit the logged duration. They are possibilities, not confirmed corrections; check recordings and adjacent flights.",
      bundle: .module
    )
    guard totalContainsWholeDays else { return summary }
    return summary + " "
      + String(
        localized:
          "Total time also contains whole days; review every credited time after confirming the dates.",
        bundle: .module
      )
  }

  private func isNearWholeHours(elapsed: Double, total: UInt) -> Bool {
    let difference = elapsed - Double(total)
    let hours = difference / Self.minutesPerHour
    return abs(difference) > Double(toleranceMinutes)
      && abs(hours - hours.rounded(.toNearestOrEven)) <= Double(toleranceMinutes)
        / Self.minutesPerHour
  }
}

extension FindingCollector {
  /// Attaches a flight's time diagnosis, if it has one, to its findings of some rules.
  mutating func attachTimeDiagnosis(
    of flight: AuditedFlight,
    toFindingsOf rules: [ConsistencyRule],
    context: ConsistencyContext
  ) {
    let diagnosis = TimeDiagnosis(
      toleranceMinutes: context.tolerances.timeToleranceMinutes,
      maximumMinutes: context.maximumMinutes(for: flight)
    )
    guard let analysis = diagnosis.analysis(of: flight) else { return }
    for rule in rules {
      for finding in findings(of: rule, involving: flight.id) { attach(analysis, to: finding.id) }
    }
  }
}
