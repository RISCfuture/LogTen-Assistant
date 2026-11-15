import LogbookModel
import Regulations
import SwiftUI

/// The inspector for the Violations table, laid out like LogTen's: a Checks section with the
/// selected flight's violations and their regulations, then the flight's details.
struct ViolationInspector: View {
  let session: LogbookSession

  private var selectedFlight: Flight? {
    guard session.selectedFlightIDs.count == 1, let id = session.selectedFlightIDs.first else {
      return nil
    }
    return session.flight(id)
  }

  var body: some View {
    Group {
      if let flight = selectedFlight {
        FlightViolationsPage(session: session, flight: flight)
      } else if session.selectedFlightIDs.isEmpty {
        ContentUnavailableView(
          "No Flight Selected",
          systemImage: "airplane",
          description: Text("Select a flight to see its violations and details.")
        )
      } else {
        ContentUnavailableView(
          "\(session.selectedFlightIDs.count, format: .number) Flights Selected",
          systemImage: "airplane"
        )
      }
    }
    .accessibilityIdentifier("violationInspector")
  }
}

/// A flight's violations and details.
private struct FlightViolationsPage: View {
  private static let violationSpacing = 12.0

  let session: LogbookSession
  let flight: Flight

  private var violations: [Violation] {
    session.regulationReport?.violations(on: flight.id) ?? []
  }

  var body: some View {
    InspectorPage {
      if !violations.isEmpty {
        InspectorSection(String(localized: "Checks")) {
          VStack(alignment: .leading, spacing: Self.violationSpacing) {
            ForEach(violations) { violation in
              ViolationSummary(violation: violation)
            }
          }
        }
      }
      FlightDetailsSections(
        details: FlightDetails(
          flight: flight,
          customFields: session.logbook?.customFields ?? [],
          timeZone: session.settings.pilot.homeTimeZone
        )
      )
    }
  }
}

/// One violation: the rule, what was missing and the regulation, linked when it is online.
private struct ViolationSummary: View {
  let violation: Violation

  private var citation: AttributedString {
    var citation = AttributedString(violation.citation)
    citation.link = violation.citationURL.webLink
    return citation
  }

  var body: some View {
    VStack(alignment: .leading) {
      InspectorSubheading(violation.rule.title)
      Text(violation.explanation)
      Text("Regulation: \(citation)")
        .accessibilityIdentifier("violationCitation")
    }
  }
}

#Preview(
  "Selected Flight",
  traits: .sampleSession { session in
    session.sidebarSelection = .violations(nil)
    session.selectedFlightIDs = [PreviewHelper.flight.id]
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { ViolationInspector(session: session) }
}

#Preview("No Selection", traits: .sampleSession { $0.sidebarSelection = .violations(nil) }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { ViolationInspector(session: session) }
}

#Preview(
  "Several Selected",
  traits: .sampleSession { session in
    session.sidebarSelection = .violations(nil)
    session.selectedFlightIDs = Set(session.logbook?.flights.prefix(3).map(\.id) ?? [])
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  InspectorColumnPreview { ViolationInspector(session: session) }
}
