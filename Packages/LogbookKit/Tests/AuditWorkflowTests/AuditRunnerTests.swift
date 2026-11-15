import Audit
import AuditWorkflow
import FlightSources
import LogbookModel
import References
import Testing

@Suite
struct `Audit runner` {
  private let runner = AuditRunner()

  @Test
  func `files a FlySto time difference under aircraft comparisons with its change`() async throws {
    let inputs = AuditInputs(
      logbook: logbook([flight("A")]),
      settings: LogbookSettings(),
      flyStoRecords: [record()]
    )

    let run = try await runner.run(inputs)

    let finding = try #require(run.findings(in: .aircraftComparisons).first)
    #expect(finding.rule == .telemetryTime)
    #expect(finding.corrections.flatMap(\.changes).map(\.field) == [.flightActualArrivalTime])
    #expect(run.flyStoRecord(for: finding.recordIDs[0])?.id == "rec")
    #expect(run.findings(in: .logbookConsistency).isEmpty)
  }

  @Test
  func `keeps the corrections on a locked flight and says why they need a manual edit`()
    async throws
  {
    let inputs = AuditInputs(
      logbook: logbook([flight("A", isLocked: true)]),
      settings: LogbookSettings(),
      flyStoRecords: [record()]
    )

    let run = try await runner.run(inputs)

    let finding = try #require(run.findings(in: .aircraftComparisons).first)
    #expect(finding.corrections.flatMap(\.changes).map(\.field) == [.flightActualArrivalTime])
    #expect(finding.correctionRestriction == .locked)
  }

  @Test
  func `matches a record by its clock times when its route disagrees`() async throws {
    let inputs = AuditInputs(
      logbook: logbook([flight("A")]),
      settings: LogbookSettings(),
      flyStoRecords: [record(from: "KPAO", to: "KHAF")]
    )

    let run = try await runner.run(inputs)

    #expect(run.flyStoMatches.map(\.basis) == [.twoUTCAnchors])
    #expect(run.findings(in: .aircraftComparisons).map(\.rule).contains(.telemetryTime))
  }

  @Test
  func `drops the findings of disabled rules`() async throws {
    let overNight = flight("A", times: FlightTimes(total: 65, night: 90))
    var settings = LogbookSettings()

    let enabled = try await runner.run(
      AuditInputs(logbook: logbook([overNight]), settings: settings)
    )
    let rule = try #require(enabled.findings(in: .logbookConsistency).first?.rule)
    settings.rules.disabledRules = [rule]
    let disabled = try await runner.run(
      AuditInputs(logbook: logbook([overNight]), settings: settings)
    )

    #expect(!disabled.findings.map(\.rule).contains(rule))
  }

  @Test
  func `notes the audits that had no data to work from`() async throws {
    let run = try await runner.run(
      AuditInputs(logbook: logbook([flight("A")]), settings: LogbookSettings())
    )

    #expect(Set(run.notes.map(\.subject)) == [.flySto, .adsb, .airportData])
  }
}
