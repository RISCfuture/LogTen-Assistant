import Foundation
import LogbookModel

/// Flags custom time fields that exceed total time, each compared with total time on its own.
struct CustomTimeBoundsCheck: ConsistencyCheck {
  var rules: [ConsistencyRule] { [.customTimeBounds] }

  func check(_ context: ConsistencyContext, into collector: inout FindingCollector) {
    let toleranceMinutes = context.tolerances.timeToleranceMinutes
    for flight in context.flights where !flight.isSimulator {
      guard let total = flight.number("totaltime") else { continue }
      for key in context.options.boundedCustomTimeFields {
        let field = AuditedFlight.name(of: key)
        guard let logged = flight.number(field), logged > total + Double(toleranceMinutes) else {
          continue
        }
        let label = context.logbook.customField(for: key)?.title ?? key.rawValue
        let finding = collector.emit(
          .customTimeBounds,
          [flight.id],
          message: String(localized: "\(label) exceeds total time.", bundle: .module),
          evidence: [
            "field": .string(field),
            "label": .string(label),
            "logged": .double(logged),
            "total_minutes": .double(total),
            "excess_minutes": .double(logged - total),
            "tolerance_minutes": .integer(Int(toleranceMinutes))
          ],
          severity: .discrepancy
        )
        collector.attach(followUp(label: label, logged: logged, total: total), to: finding.id)
      }
    }
  }

  private func followUp(label: String, logged: Double, total: Double) -> FindingAnalysis {
    FindingAnalysis(
      summary: String(
        localized:
          "Review \(label): \(logged, format: .number.grouping(.never)) minutes versus total \(total, format: .number.grouping(.never)) minutes.",
        bundle: .module
      ),
      notes: [
        String(
          localized:
            "Each configured field is checked on its own; overlapping categories aren’t added together.",
          bundle: .module
        ),
        String(
          localized:
            "Confirm which value is wrong before changing credit. An exact replacement isn’t inferred.",
          bundle: .module
        )
      ]
    )
  }
}
