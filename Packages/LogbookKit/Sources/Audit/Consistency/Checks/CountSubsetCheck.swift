import Foundation
import LogbookModel

/// Flags landing and takeoff counts above the counts that contain them, and night full stops
/// logged without total full stops.
struct CountSubsetCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.missingFullStops, .nightFullStopsSubset, .countSubset] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    let nightFullStops = context.mapping[.nightFullStops].map(AuditedFlight.name)
    let pairs = countSubsets(nightFullStops: nightFullStops)
    for flight in context.flights {
      for (child, parent) in pairs {
        check(child, parent, nightFullStops: nightFullStops, of: flight, context, &collector)
      }
    }
  }

  /// The count pairs whose first member must not exceed the second, by lowercased attribute
  /// name. Pairs that need an unmapped role are left out.
  private func countSubsets(nightFullStops: String?) -> [(child: String, parent: String)] {
    let nightPairs = nightFullStops.map { [($0, "fullstops"), ($0, "nightlandings")] } ?? []
    return nightPairs + [
      ("fullstops", "totallandings"), ("nightlandings", "totallandings"),
      ("daylandings", "totallandings"), ("nighttakeoffs", "totaltakeoffs"),
      ("daytakeoffs", "totaltakeoffs")
    ]
  }

  private func check(
    _ child: String,
    _ parent: String,
    nightFullStops: String?,
    of flight: AuditedFlight,
    _ context: ConsistencyContext,
    _ collector: inout FindingCollector
  ) {
    guard let count = flight.number(child), count > 0 else { return }
    let isNightFullStops = child == nightFullStops && parent == "fullstops"
    let total = flight.number(parent)
    if isNightFullStops && (total ?? 0) == 0 {
      collector.emit(
        .missingFullStops,
        [flight.id],
        message: String(
          localized: "Night full stops are recorded but total full stops are missing.",
          bundle: .module
        ),
        evidence: .object([child: flight[child].evidenceJSON, parent: .null]),
        severity: .questionable
      )
    } else if let total, count > total {
      let childTitle = context.title(of: child, in: flight)
      let parentTitle = context.title(of: parent, in: flight)
      collector.emit(
        isNightFullStops ? .nightFullStopsSubset : .countSubset,
        [flight.id],
        message: String(localized: "\(childTitle) exceeds \(parentTitle).", bundle: .module),
        evidence: .object([child: flight[child].evidenceJSON, parent: flight[parent].evidenceJSON]),
        severity: .discrepancy
      )
    }
  }
}
