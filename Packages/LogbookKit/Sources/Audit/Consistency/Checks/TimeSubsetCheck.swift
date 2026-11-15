import Foundation
import LogbookModel

/**
 Flags night, instrument, role, solo and instruction times above total time, instrument times that
 together are longer than total time, and cross-country night time above cross-country or night
 time, outside simulators.

 Actual and simulated instrument time are separate periods, so their sum is bounded by total
 time too, though each alone may not be. Where a time is above its limit, the finding offers
 limiting it to the limit.
 */
struct TimeSubsetCheck: ConsistencyCheck {
  private static let totalTimeSubsets = [
    "night", "actualinstrument", "simulatedinstrument", "pic", "sic", "p1us", "solo",
    "dualreceived", "dualgiven"
  ]
  private static let instrumentTimes = ["actualinstrument", "simulatedinstrument"]
  private static let crossCountryNight = "crosscountrynight"

  var rules: [ConsistencyRule] { [.timeSubset] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    for flight in context.flights where !flight.isSimulator {
      checkTotalTimeSubsets(of: flight, context, &collector)
      checkCrossCountryNight(of: flight, context, &collector)
    }
  }

  private func checkTotalTimeSubsets(
    of flight: AuditedFlight,
    _ context: ConsistencyContext,
    _ collector: inout FindingCollector
  ) {
    guard let total = flight.number("totaltime"), total != 0 else { return }
    for name in Self.totalTimeSubsets {
      guard let time = flight.number(name), time != 0, time > total else { continue }
      emit(
        flight,
        context,
        message: String(
          localized: "\(context.title(of: name, in: flight)) exceeds total time.",
          bundle: .module
        ),
        exceeding: name,
        limit: "totaltime",
        into: &collector
      )
    }
    let instruments = Self.instrumentTimes.compactMap { flight.number($0) }.reduce(0, +)
    let eachFits = Self.instrumentTimes.allSatisfy { (flight.number($0) ?? 0) <= total }
    guard eachFits, instruments > total else { return }
    collector.emit(
      .timeSubset,
      [flight.id],
      message: String(
        localized: "Instrument times together exceed total time.",
        bundle: .module
      ),
      evidence: .object(
        Dictionary(
          uniqueKeysWithValues: (Self.instrumentTimes + ["totaltime"]).map {
            ($0, flight[$0].evidenceJSON)
          }
        )
      ),
      severity: .discrepancy,
      explanation: String(
        localized:
          "Actual and simulated instrument time are separate periods, so together they can’t be longer than the flight.",
        bundle: .module
      ),
      recommendation: String(
        localized:
          "Correct the instrument times, or the total time if it is understated.",
        bundle: .module
      )
    )
  }

  private func checkCrossCountryNight(
    of flight: AuditedFlight,
    _ context: ConsistencyContext,
    _ collector: inout FindingCollector
  ) {
    guard let time = flight.number(Self.crossCountryNight), time != 0 else { return }
    for limit in ["crosscountry", "night"] where time > (flight.number(limit) ?? 0) {
      emit(
        flight,
        context,
        message: String(
          localized:
            "\(context.title(of: Self.crossCountryNight, in: flight)) exceeds \(context.title(of: limit, in: flight)).",
          bundle: .module
        ),
        exceeding: Self.crossCountryNight,
        limit: limit,
        into: &collector
      )
    }
  }

  private func emit(
    _ flight: AuditedFlight,
    _ context: ConsistencyContext,
    message: String,
    exceeding name: String,
    limit: String,
    into collector: inout FindingCollector
  ) {
    collector.emit(
      .timeSubset,
      [flight.id],
      message: message,
      evidence: .object([name: flight[name].evidenceJSON, limit: flight[limit].evidenceJSON]),
      severity: .discrepancy,
      explanation: String(
        localized:
          "\(context.title(of: name, in: flight)) is part of \(context.title(of: limit, in: flight)), so it can’t be longer.",
        bundle: .module
      ),
      recommendation: String(
        localized:
          "Lower the time to fit, or correct \(context.title(of: limit, in: flight)) if it is understated.",
        bundle: .module
      ),
      corrections: limitingOptions(flight, context, name: name, limit: limit)
    )
  }

  private func limitingOptions(
    _ flight: AuditedFlight,
    _ context: ConsistencyContext,
    name: String,
    limit: String
  ) -> [CorrectionOption] {
    guard let key = flight.keys[name], let value = flight.number(limit) else { return [] }
    let title = context.title(of: name, in: flight)
    return [
      CorrectionOption(
        title: String(
          localized: "Limit \(title) to \(context.title(of: limit, in: flight))",
          bundle: .module
        ),
        detail: String(
          localized: "\(title) becomes \(FlightTimeText.hours(Double(value))).",
          bundle: .module
        ),
        changes: [flight.change(key, to: .integer(Int(value)))]
      )
    ]
  }
}
