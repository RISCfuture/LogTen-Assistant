import Foundation
import LogbookModel
import Testing

@testable import Regulations

@Suite
struct `Night vision goggle rules` {
  private func nvg(_ id: String, _ date: Date, takeoffs: UInt = 3, landings: UInt = 3) -> Flight {
    .fixture(id, date) {
      $0.counts.nightVisionGoggleTakeoffs = takeoffs
      $0.counts.nightVisionGoggleLandings = landings
    }
  }

  private func flagged(_ scenario: Scenario, by rule: RegulationRule) async throws -> Bool {
    try await scenario.flagged(by: rule).contains("a")
  }

  private func subject(_ date: Date = day(2025, 6, 1), passengers: Bool = false) -> Flight {
    nvg("a", date, takeoffs: 1, landings: 1).withPassengers(passengers)
  }

  @Test
  func `passes with three NVG takeoffs and landings in the preceding 4 months`() async throws {
    let scenario = Scenario(flights: [nvg("lap", day(2025, 2, 1)), subject()])
    #expect(!(try await flagged(scenario, by: .noNVGCurrency)))
  }

  @Test
  func `passes on a proficiency check even with fewer takeoffs and landings`() async throws {
    // A pilot with a proficiency check is current whatever else the logbook holds, so neither
    // a short count of takeoffs nor of landings may flag the flight.
    for (takeoffs, landings) in [(UInt(2), UInt(3)), (3, 2), (0, 0)] {
      let check = Flight.fixture("check", day(2025, 4, 1)) {
        $0.mark(.nightVisionGoggleProficiencyCheck)
        $0.counts.nightVisionGoggleTakeoffs = takeoffs
        $0.counts.nightVisionGoggleLandings = landings
      }
      let scenario = Scenario(flights: [check, subject()])
      #expect(!(try await flagged(scenario, by: .noNVGCurrency)))
    }
  }

  @Test
  func `flags too few takeoffs or too few landings without a check`() async throws {
    for (takeoffs, landings) in [(UInt(2), UInt(3)), (3, 2)] {
      let scenario = Scenario(flights: [
        nvg("lap", day(2025, 4, 1), takeoffs: takeoffs, landings: landings), subject()
      ])
      #expect(try await flagged(scenario, by: .noNVGCurrency))
    }
  }

  @Test
  func `counts back 4 calendar months for solo flights and 2 for passengers`() async throws {
    let lap = nvg("lap", day(2025, 2, 28))
    let solo = Scenario(flights: [lap, subject(day(2025, 6, 30))])
    let carrying = Scenario(flights: [lap, subject(day(2025, 6, 30), passengers: true)])

    #expect(!(try await flagged(solo, by: .noNVGCurrency)))
    #expect(!(try await flagged(solo, by: .noNVGPassengerCurrency)))
    #expect(try await flagged(carrying, by: .noNVGPassengerCurrency))
    #expect(!(try await flagged(carrying, by: .noNVGCurrency)))
  }

  @Test
  func `reports a passenger flight under the passenger rule`() async throws {
    let scenario = Scenario(flights: [subject(passengers: true)])
    let found = try await scenario.violations(of: .noNVGPassengerCurrency)

    #expect(found.map(\.rule) == [.noNVGPassengerCurrency])
  }

  @Test
  func `ignores flights without NVG takeoffs and landings, and dual received`() async throws {
    var dual = subject()
    dual.times.dualReceived = 60
    let scenario = Scenario(flights: [.fixture("plain", day(2025, 6, 1)), dual])
    #expect(!(try await flagged(scenario, by: .noNVGCurrency)))
  }

  @Test
  func `does not accept a proficiency check in another category`() async throws {
    let check = Flight.fixture("check", day(2025, 4, 1), in: .helicopter) {
      $0.mark(.nightVisionGoggleProficiencyCheck)
    }
    let scenario = Scenario(flights: [check, subject()])
    #expect(try await flagged(scenario, by: .noNVGCurrency))
  }
}

extension Flight {
  fileprivate func withPassengers(_ carrying: Bool) -> Flight {
    var flight = self
    if carrying { flight.carryPassenger() }
    return flight
  }
}

@Suite
struct `Proficiency check rules` {
  private func check(_ id: String, _ date: Date, in aircraft: Aircraft = .jet) -> Flight {
    .fixture(id, date, in: aircraft) { $0.mark(.proficiencyCheck) }
  }

  @Test
  func `applies only to aircraft that require a type rating`() async throws {
    let scenario = Scenario(flights: [.fixture("a", day(2025, 3, 1), in: .cessna)])
    #expect(try await scenario.flagged(by: .noProficiencyCheck).isEmpty)
    #expect(try await scenario.flagged(by: .noProficiencyCheckInType).isEmpty)
  }

  @Test
  func `applies to aircraft the settings mark as needing a proficiency check`() async throws {
    var scenario = Scenario(flights: [.fixture("a", day(2025, 3, 1), in: .cessna)])
    scenario.settings.aircraft["N172"] = AircraftSettings(requiresProficiencyCheck: true)
    #expect(try await scenario.flagged(by: .noProficiencyCheck) == ["a"])
  }

  @Test
  func `requires a check within 12 calendar months`() async throws {
    let scenario = Scenario(flights: [
      check("check", day(2024, 3, 31)), .fixture("last-day", day(2025, 3, 31), in: .jet),
      .fixture("lapsed", day(2025, 4, 1), in: .jet)
    ])
    #expect(try await scenario.flagged(by: .noProficiencyCheck) == ["lapsed"])
  }

  @Test
  func `accepts a check in any type for the 12-month rule`() async throws {
    let scenario = Scenario(flights: [
      check("check", day(2025, 1, 1), in: .airliner), .fixture("a", day(2025, 3, 1), in: .jet)
    ])
    #expect(try await scenario.flagged(by: .noProficiencyCheck).isEmpty)
  }

  @Test
  func `accepts a check credited to a month in the settings`() async throws {
    var scenario = Scenario(flights: [.fixture("a", day(2025, 3, 1), in: .jet)])
    scenario.settings.rules.confirmedCurrencyEvents = [
      ConfirmedCurrencyEvent(date: DateComponents(year: 2024, month: 3), kind: .proficiencyCheck)
    ]
    #expect(try await scenario.flagged(by: .noProficiencyCheck).isEmpty)
  }

  @Test
  func `exempts dual received and the check itself`() async throws {
    let scenario = Scenario(flights: [
      .fixture("dual", day(2025, 3, 1), in: .jet) { $0.times.dualReceived = 60 },
      check("check", day(2025, 3, 2))
    ])
    #expect(try await scenario.flagged(by: .noProficiencyCheck).isEmpty)
    #expect(try await scenario.flagged(by: .noProficiencyCheckInType).isEmpty)
  }

  @Test
  func `requires a check in the same type within 24 calendar months`() async throws {
    let scenario = Scenario(flights: [
      check("check", day(2023, 3, 31)), .fixture("last-day", day(2025, 3, 31), in: .jet),
      .fixture("lapsed", day(2025, 4, 1), in: .jet)
    ])
    #expect(try await scenario.flagged(by: .noProficiencyCheckInType) == ["lapsed"])
  }

  @Test
  func `does not accept a check in another type for the in-type rule`() async throws {
    let scenario = Scenario(flights: [
      check("check", day(2025, 1, 1), in: .airliner), .fixture("a", day(2025, 3, 1), in: .jet)
    ])
    #expect(try await scenario.flagged(by: .noProficiencyCheckInType) == ["a"])
  }

  @Test
  func `accepts a full flight simulator check of the type`() async throws {
    let sim = Aircraft.simulator(representing: "SF50", device: .FFS)
    let scenario = Scenario(flights: [
      check("check", day(2025, 1, 1), in: sim), .fixture("a", day(2025, 3, 1), in: .jet)
    ])
    #expect(try await scenario.flagged(by: .noProficiencyCheckInType).isEmpty)
  }
}

@Suite
struct `Second-in-command currency rule` {
  private func sic(_ id: String, _ date: Date, in aircraft: Aircraft = .jet) -> Flight {
    .fixture(id, date, in: aircraft) {
      $0.times.PIC = 0
      $0.times.SIC = 60
    }
  }

  @Test
  func `needs three takeoffs and landings in type in 90 days`() async throws {
    let enough = Scenario(flights: [
      .landings("lap", day(2025, 5, 1), in: .jet), sic("a", day(2025, 6, 1))
    ])
    let short = Scenario(flights: [
      .landings("lap", day(2025, 5, 1), in: .jet) { $0.counts.dayTakeoffs = 2 },
      sic("a", day(2025, 6, 1))
    ])
    let otherType = Scenario(flights: [
      .landings("lap", day(2025, 5, 1), in: .airliner), sic("a", day(2025, 6, 1))
    ])

    #expect(try await enough.flagged(by: .noSICCurrency).isEmpty)
    #expect(try await short.flagged(by: .noSICCurrency) == ["a"])
    #expect(try await otherType.flagged(by: .noSICCurrency) == ["a"])
  }

  @Test
  func `applies only to second-in-command flights in type-rated aircraft without passengers`()
    async throws
  {
    var withPassenger = sic("pax", day(2025, 6, 1))
    withPassenger.carryPassenger()
    let scenario = Scenario(flights: [
      sic("light", day(2025, 6, 2), in: .cessna), withPassenger,
      .fixture("pic", day(2025, 6, 3), in: .jet)
    ])
    #expect(try await scenario.flagged(by: .noSICCurrency).isEmpty)
  }
}

@Suite
struct `Flight instruction rules` {
  private func instruction(
    _ id: String,
    _ date: Date,
    hours: UInt,
    in aircraft: Aircraft = .cessna
  ) -> Flight {
    .fixture(id, date, in: aircraft) {
      $0.times.dualGiven = hours * 60
      $0.times.PIC = hours * 60
    }
  }

  @Test
  func `counts the flight itself toward eight hours`() async throws {
    let scenario = Scenario(flights: [
      instruction("exact", day(2025, 3, 1), hours: 8),
      instruction("over", day(2025, 3, 5), hours: 9)
    ])
    #expect(try await scenario.flagged(by: .dualGiven8In24) == ["over"])
  }

  @Test
  func `adds flights that started in the preceding 24 hours`() async throws {
    let scenario = Scenario(flights: [
      instruction("first", day(2025, 3, 1, hour: 8), hours: 5),
      instruction("second", day(2025, 3, 2, hour: 7), hours: 4),
      instruction("third", day(2025, 3, 2, hour: 8), hours: 4)
    ])
    let found = try await scenario.violations(of: .dualGiven8In24)

    #expect(found.map(\.flightID.rawValue) == ["second"])
    #expect(found[0].contributingFlightIDs == [RecordID(rawValue: "first")])
  }

  @Test
  func `excludes a flight that started exactly 24 hours earlier`() async throws {
    let scenario = Scenario(flights: [
      instruction("first", day(2025, 3, 1, hour: 8), hours: 5),
      instruction("second", day(2025, 3, 2, hour: 8), hours: 4)
    ])
    #expect(try await scenario.flagged(by: .dualGiven8In24).isEmpty)
  }

  @Test
  func `uses logged block-out times to order flights on one date`() async throws {
    var morning = instruction("morning", day(2025, 3, 1, hour: 0), hours: 5)
    morning.events.out = day(2025, 3, 1, hour: 14)
    var evening = instruction("evening", day(2025, 3, 1, hour: 0), hours: 4)
    evening.events.out = day(2025, 3, 1, hour: 20)

    let found = try await Scenario(flights: [morning, evening]).flagged(by: .dualGiven8In24)

    #expect(found == ["evening"])
  }

  @Test
  func `requires five hours in make and model before instructing in a multi-engine airplane`()
    async throws
  {
    let scenario = Scenario(flights: [
      .fixture("history", day(2024, 1, 1), in: .twin) { $0.times.PIC = 4 * 60 + 59 },
      instruction("short", day(2025, 3, 1), hours: 1, in: .twin),
      .fixture("more", day(2025, 3, 2), in: .twin) { $0.times.PIC = 1 },
      instruction("enough", day(2025, 3, 3), hours: 1, in: .twin)
    ])
    #expect(try await scenario.flagged(by: .dualGivenTimeInType) == ["short"])
  }

  @Test
  func `ignores single-engine airplanes and other makes and models`() async throws {
    let scenario = Scenario(flights: [
      .fixture("other", day(2024, 1, 1), in: .airliner) { $0.times.PIC = 10 * 60 },
      instruction("single", day(2025, 3, 1), hours: 1, in: .cessna),
      instruction("twin", day(2025, 3, 2), hours: 1, in: .twin)
    ])
    #expect(try await scenario.flagged(by: .dualGivenTimeInType) == ["twin"])
  }

  @Test
  func `requires time in type for helicopters`() async throws {
    let scenario = Scenario(flights: [
      instruction("heli", day(2025, 3, 1), hours: 1, in: .helicopter)
    ])
    #expect(try await scenario.flagged(by: .dualGivenTimeInType) == ["heli"])
  }
}
