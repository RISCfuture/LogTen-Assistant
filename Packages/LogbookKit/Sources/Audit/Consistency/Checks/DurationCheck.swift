import Foundation
import LogbookModel

/// Flags out-to-in intervals that differ from total time and flights longer than is plausible,
/// with a diagnosis of likely date errors. An entry whose block time disagrees isn't also
/// flagged as implausible while the block-time rule is on.
struct DurationCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.blockDuration, .implausibleDuration] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights {
      let elapsed = elapsedMinutes(of: flight)
      checkBlockTime(of: flight, elapsed: elapsed, context, into: &collector)
      checkPlausibility(of: flight, elapsed: elapsed, context, into: &collector)
      collector.attachTimeDiagnosis(of: flight, toFindingsOf: rules, context: context)
    }
  }

  private func elapsedMinutes(of flight: AuditedFlight) -> Double? {
    flight.flight.events.out.flatMap { out in
      flight.flight.events.in.map { PythonTimestamp.minutes(from: out, to: $0) }
    }
  }

  private func checkBlockTime(
    of flight: AuditedFlight,
    elapsed: Double?,
    _ context: ConsistencyContext,
    into collector: inout FindingCollector
  ) {
    let total = flight.flight.times.total
    guard let elapsed, elapsed >= 0, total > 0,
      abs(elapsed - Double(total)) > Double(context.tolerances.timeToleranceMinutes)
    else { return }
    collector.emit(
      .blockDuration,
      [flight.id],
      message: String(
        localized: "The out-to-in interval differs from the logged total time.",
        bundle: .module
      ),
      evidence: ["elapsed_minutes": .double(elapsed), "logged_minutes": .integer(Int(total))],
      severity: .questionable,
      explanation: String(
        localized:
          "The time between out and in is \(FlightTimeText.hours(elapsed)), but total time is \(FlightTimeText.hours(total)).",
        bundle: .module
      ),
      recommendation: String(
        localized:
          "Check the times and the total. If you logged only part of the flight, such as time as a safety pilot, keep it as logged.",
        bundle: .module
      ),
      corrections: elapsedOptions(
        of: flight,
        elapsed: elapsed,
        maximum: context.maximumMinutes(for: flight),
        total: total
      )
    )
  }

  private func checkPlausibility(
    of flight: AuditedFlight,
    elapsed: Double?,
    _ context: ConsistencyContext,
    into collector: inout FindingCollector
  ) {
    let total = flight.flight.times.total
    let maximum = context.maximumMinutes(for: flight)
    let hasBlockFinding =
      ConsistencyRule.blockDuration.isEnabled(in: context.settings.rules)
      && !collector.findings(of: .blockDuration, involving: flight.id).isEmpty
    guard !flight.isSimulator, max(elapsed ?? 0, Double(total)) > Double(maximum),
      !hasBlockFinding
    else { return }
    collector.emit(
      .implausibleDuration,
      [flight.id],
      message: String(
        localized: "The flight is longer than the configured review threshold.",
        bundle: .module
      ),
      evidence: [
        "elapsed_minutes": elapsed.map(JSONValue.double) ?? .integer(0),
        "logged_minutes": .integer(Int(total)),
        "threshold_minutes": .integer(Int(maximum))
      ],
      severity: .questionable,
      explanation: String(
        localized:
          "A flight of \(FlightTimeText.hours(max(elapsed ?? 0, Double(total)))) hours is longer than the \(FlightTimeText.hours(maximum)) this aircraft is expected to fly in one entry, which usually means a date, a time or the total was mistyped.",
        bundle: .module
      ),
      recommendation: String(
        localized:
          "Correct the total or the times. If one entry really holds this long a flight, keep it as logged.",
        bundle: .module
      )
    )
  }

  /// An option that sets total time to the out-to-in interval, offered when that interval is
  /// plausible and total time isn't.
  private func elapsedOptions(
    of flight: AuditedFlight,
    elapsed: Double?,
    maximum: UInt,
    total: UInt
  ) -> [CorrectionOption] {
    guard let elapsed, elapsed > 0, elapsed <= Double(maximum), total > maximum else { return [] }
    let minutes = Int(elapsed.rounded())
    let update = flight.settingTotalTime(to: minutes)
    return [
      CorrectionOption(
        title: String(localized: "Use the Out-to-In Time", bundle: .module),
        detail: totalDetail(minutes: minutes, limited: update.limitedTitles),
        changes: update.changes
      )
    ]
  }

  private func totalDetail(minutes: Int, limited: [String]) -> String {
    let detail = String(
      localized:
        "Total time becomes \(FlightTimeText.hours(Double(minutes))), the time from out to in.",
      bundle: .module
    )
    guard !limited.isEmpty else { return detail }
    let limits = String(
      localized:
        "Also limited to the new total, as LogTen would do: \(FlightTimeText.list(limited)).",
      bundle: .module
    )
    return detail + " " + limits
  }
}
