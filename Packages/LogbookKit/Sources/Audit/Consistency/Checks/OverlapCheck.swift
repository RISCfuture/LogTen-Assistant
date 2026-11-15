import Foundation
import LogbookModel

/// Finds entries whose out-to-in intervals overlap, and links each overlap to a duration
/// finding that may explain it.
struct OverlapCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.flightOverlap] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    let timed = context.flights.compactMap { flight -> (AuditedFlight, Date, Date)? in
      guard let out = flight.flight.events.out, let `in` = flight.flight.events.in else {
        return nil
      }
      return (flight, out, `in`)
    }
    .sorted { ($0.1, $0.0.id) < ($1.1, $1.0.id) }

    let explanations = durationFindingsWithCandidates(in: collector)
    for (index, (first, firstOut, firstIn)) in timed.enumerated() {
      for (second, secondOut, secondIn) in timed[(index + 1)...] {
        if secondOut >= firstIn { break }
        let finding = collector.emit(
          .flightOverlap,
          [first.id, second.id],
          message: String(
            localized: "The logged flight intervals overlap; verify pilot attribution.",
            bundle: .module
          ),
          evidence: [
            "first": [
              .string(PythonTimestamp.isoformat(firstOut)),
              .string(PythonTimestamp.isoformat(firstIn))
            ],
            "second": [
              .string(PythonTimestamp.isoformat(secondOut)),
              .string(PythonTimestamp.isoformat(secondIn))
            ]
          ],
          severity: .questionable
        )
        let related = finding.recordIDs.compactMap { explanations[$0] }
        guard !related.isEmpty else { continue }
        collector.attach(
          FindingAnalysis(
            summary: String(
              localized:
                "This overlap may be a consequence of a date error. Review the linked duration finding before changing either flight.",
              bundle: .module
            ),
            relatedFindings: related
          ),
          to: finding.id
        )
      }
    }
  }

  private func durationFindingsWithCandidates(in collector: FindingCollector) -> [RecordID:
    FindingID]
  {
    var explanations = [RecordID: FindingID]()
    for finding in collector.findings
    where finding.rule == ConsistencyRule.blockDuration.id
      || finding.rule == ConsistencyRule.implausibleDuration.id
    {
      guard collector.analysis(of: finding.id)?.dateErrorCandidates.isEmpty == false else {
        continue
      }
      for id in finding.recordIDs { explanations[id] = finding.id }
    }
    return explanations
  }
}
