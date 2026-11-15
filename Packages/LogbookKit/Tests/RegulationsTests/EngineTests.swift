import Foundation
import LogbookModel
import Testing

@testable import Regulations

@Suite
struct `Regulation engine` {
  @Test
  func `reports a rule with unmapped fields as not evaluated`() async throws {
    var scenario = Scenario(flights: [.fixture("a", day(2025, 3, 1))])
    try scenario.settings.fieldMapping.assign(nil, to: .checkride)

    let report = try await RegulationEngine(settings: scenario.settings)
      .evaluate(scenario.flights)

    #expect(report.statuses[.noFlightReview] == .notEvaluated(missingRoles: [.checkride]))
    #expect(report.unevaluatedRules == [.noFlightReview])
    #expect(report.violations(of: .noFlightReview).isEmpty)
  }

  @Test
  func `skips instructor rules for a pilot who is not an instructor`() {
    let scenario = Scenario { $0.pilot.instructorRatings = [] }
    let engine = RegulationEngine(settings: scenario.settings)

    #expect(engine.status(of: .dualGiven8In24) == .skipped(.notFlightInstructor))
    #expect(engine.status(of: .dualGivenTimeInType) == .skipped(.notFlightInstructor))
    #expect(engine.status(of: .noPassengerCurrency) == .evaluated)
  }

  @Test
  func `skips instructor rules when instruction activity is ignored`() {
    let scenario = Scenario { $0.pilot.ignoresInstructionActivity = true }

    let status = RegulationEngine(settings: scenario.settings).status(of: .dualGiven8In24)

    #expect(status == .skipped(.ignoresInstructionActivity))
  }

  @Test
  func `skips IFR currency for a pilot without an instrument rating`() {
    let scenario = Scenario { $0.pilot.instrumentRatings = [] }

    #expect(
      RegulationEngine(settings: scenario.settings).status(of: .noIFRCurrency)
        == .skipped(.noInstrumentRating)
    )
  }

  @Test
  func `skips flight review for a student pilot`() {
    let scenario = Scenario { $0.pilot.certificateLevel = .student }

    #expect(
      RegulationEngine(settings: scenario.settings).status(of: .noFlightReview)
        == .skipped(.studentPilot)
    )
  }

  @Test
  func `skips a disabled rule`() async throws {
    let scenario = Scenario(flights: [.fixture("a", day(2025, 3, 1))]) {
      $0.rules.disabledRules = [RegulationRule.noFlightReview.id]
    }

    let report = try await RegulationEngine(settings: scenario.settings)
      .evaluate(scenario.flights)

    #expect(report.statuses[.noFlightReview] == .skipped(.disabled))
    #expect(report.violations.isEmpty)
  }

  @Test
  func `does not flag sessions in a simulator`() async throws {
    let scenario = Scenario(flights: [
      .fixture("sim", day(2025, 4, 1), in: .simulator(representing: "B738", device: .FFS)) {
        $0.carryPassenger()
      }
    ])

    let report = try await RegulationEngine(settings: scenario.settings)
      .evaluate(scenario.flights)

    #expect(report.violations.isEmpty)
  }

  @Test
  func `groups violations by flight, oldest first, in rule order`() async throws {
    let scenario = Scenario(flights: [
      .fixture("later", day(2025, 5, 1)) { $0.carryPassenger() },
      .fixture("earlier", day(2025, 4, 1)) { $0.carryPassenger() }
    ])

    let report = try await RegulationEngine(settings: scenario.settings)
      .evaluate(scenario.flights)

    #expect(report.flights.map(\.flightID.rawValue) == ["earlier", "later"])
    #expect(
      report.violations(on: RecordID(rawValue: "earlier")).map(\.rule)
        == [.noFlightReview, .noPassengerCurrency]
    )
  }

  @Test
  func `describes a violation with its citation and contributing flights`() async throws {
    let scenario = Scenario(flights: [
      .landings("lap", day(2025, 5, 1)) { $0.counts.dayLandings = 2 },
      .fixture("subject", day(2025, 5, 2)) { $0.carryPassenger() }
    ])

    let violation = try #require(
      try await scenario.violations(of: .noPassengerCurrency).first
    )

    #expect(violation.citation == "14 CFR 61.57(a)")
    #expect(
      violation.citationURL.absoluteString
        == "https://www.ecfr.gov/current/title-14/chapter-I/subchapter-D/part-61/subpart-A/section-61.57"
    )
    #expect(violation.contributingFlightIDs == [RecordID(rawValue: "lap")])
    #expect(violation.finding.rule == RegulationRule.noPassengerCurrency.id)
    #expect(violation.finding.recordIDs == [RecordID(rawValue: "subject")])
  }

  @Test
  func `links instructor rules to subpart H`() {
    #expect(RegulationRule.dualGiven8In24.citationURL.path.contains("/subpart-H/section-61.195"))
  }
}
