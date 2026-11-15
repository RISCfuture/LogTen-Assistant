import Foundation
import LogbookModel

/// Finds aircraft, places and aircraft types that share an identifier.
struct DuplicateReferenceCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.duplicateReference] }

  private static func recordKind(_ table: String) -> String {
    switch table {
      case "ZAIRCRAFT": String(localized: "aircraft", bundle: .module)
      case "ZPLACE": String(localized: "place", bundle: .module)
      default: String(localized: "aircraft type", bundle: .module)
    }
  }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    let logbook = context.logbook
    let types = Dictionary(
      (logbook.aircraft.compactMap(\.type) + logbook.flights.compactMap(\.aircraft?.type))
        .map { ($0.id, $0) }
    ) { first, _ in first }
    report("ZAIRCRAFT", logbook.aircraft.map { ($0.id, $0.registration) }, into: &collector)
    report("ZPLACE", logbook.places.map { ($0.id, $0.ICAO ?? "") }, into: &collector)
    report("ZAIRCRAFTTYPE", types.values.map { ($0.id, $0.type) }, into: &collector)
  }

  private func report(
    _ table: String,
    _ records: [(RecordID, String)],
    into collector: inout FindingCollector
  ) {
    var byIdentifier = [String: [RecordID]]()
    for (id, identifier) in records {
      let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      guard !normalized.isEmpty else { continue }
      byIdentifier[normalized, default: []].append(id)
    }
    for (identifier, ids) in byIdentifier where ids.count > 1 {
      let sorted = ids.sorted()
      collector.emit(
        .duplicateReference,
        sorted,
        message: String(
          localized: "Several \(Self.recordKind(table)) records use \(identifier).",
          bundle: .module
        ),
        evidence: [
          "table": .string(table),
          "identifier": .string(identifier),
          "record_ids": .array(sorted.map { .string($0.rawValue) })
        ],
        explanation: String(
          localized:
            "Records that share an identifier split one thing’s flights and totals across several entries.",
          bundle: .module
        ),
        recommendation: String(
          localized:
            "Merge the records in LogTen so every flight points to one. If they are different things that happen to share an identifier, keep them as logged.",
          bundle: .module
        )
      )
    }
  }
}
