import Foundation
import LogbookModel
import Testing

@testable import Regulations

@Suite
struct `Flight review rule` {
  @Test
  func `flags pilot-in-command flights with no review on record`() async throws {
    let scenario = Scenario(flights: [.fixture("a", day(2025, 3, 1))])
    #expect(try await scenario.flagged(by: .noFlightReview) == ["a"])
  }

  @Test
  func `counts a review through the end of the 24th following month`() async throws {
    let review = Flight.fixture("review", day(2023, 3, 31)) { $0.isFlightReview = true }
    let scenario = Scenario(flights: [
      review, .fixture("last-day", day(2025, 3, 31)), .fixture("first-lapsed", day(2025, 4, 1))
    ])
    #expect(try await scenario.flagged(by: .noFlightReview) == ["first-lapsed"])
  }

  @Test
  func `accepts a checkride as a review`() async throws {
    let scenario = Scenario(flights: [
      .fixture("checkride", day(2024, 1, 10)) { $0.mark(.checkride) },
      .fixture("a", day(2025, 3, 1))
    ])
    #expect(try await scenario.flagged(by: .noFlightReview).isEmpty)
  }

  @Test
  func `does not flag flights before the first checkride`() async throws {
    let scenario = Scenario(flights: [
      .fixture("failed-attempt", day(2007, 9, 11)),
      .fixture("checkride", day(2007, 9, 14)) { $0.mark(.checkride) },
      .fixture("after", day(2010, 1, 1))
    ])
    #expect(try await scenario.flagged(by: .noFlightReview) == ["after"])
  }

  @Test
  func `accepts a review confirmed in the settings`() async throws {
    var scenario = Scenario(flights: [.fixture("a", day(2025, 3, 1))])
    scenario.settings.rules.confirmedCurrencyEvents = [
      ConfirmedCurrencyEvent(date: DateComponents(year: 2023, month: 3), kind: .flightReview)
    ]
    #expect(try await scenario.flagged(by: .noFlightReview).isEmpty)
  }

  @Test
  func `exempts dual received, student solo, reviews and checkrides`() async throws {
    let scenario = Scenario(flights: [
      .fixture("dual", day(2025, 3, 1)) { $0.times.dualReceived = 60 },
      .fixture("solo", day(2025, 3, 2)) { $0.times.solo = 60 },
      .fixture("review", day(2025, 3, 3)) { $0.isFlightReview = true },
      .fixture("checkride", day(2025, 3, 4)) { $0.mark(.checkride) },
      .fixture("passenger-seat", day(2025, 3, 5)) { $0.times.PIC = 0 }
    ])
    // The review and checkride on 3/3 and 3/4 satisfy any flight dated on or after them, but
    // the exempt flights themselves are never flagged.
    #expect(try await scenario.flagged(by: .noFlightReview).isEmpty)
  }

  @Test
  func `does not count a simulator that is not credited for flight reviews`() async throws {
    let device = Aircraft.simulator(representing: "C172", device: .AATD)
    let review = Flight.fixture("sim", day(2025, 1, 1), in: device) { $0.isFlightReview = true }
    var scenario = Scenario(flights: [review, .fixture("a", day(2025, 3, 1))])
    #expect(try await scenario.flagged(by: .noFlightReview) == ["a"])

    scenario.settings.aircraft["SIM-AATD"] = AircraftSettings(simulatorCredit: [.flightReview])
    #expect(try await scenario.flagged(by: .noFlightReview).isEmpty)
  }
}

@Suite
struct `Passenger currency rule` {
  private func flagged(_ flights: [Flight], configure: (inout LogbookSettings) -> Void = { _ in })
    async throws -> Set<String>
  {
    try await Scenario(flights: flights, configure: configure).flagged(by: .noPassengerCurrency)
  }

  @Test
  func `needs three takeoffs and three landings`() async throws {
    let enough = Flight.landings("lap", day(2025, 5, 1))
    let short = Flight.landings("short", day(2025, 5, 1)) { $0.counts.dayLandings = 2 }

    #expect(
      try await flagged([enough, .fixture("a", day(2025, 5, 2)) { $0.carryPassenger() }]).isEmpty
    )
    #expect(
      try await flagged([short, .fixture("a", day(2025, 5, 2)) { $0.carryPassenger() }]) == ["a"]
    )
  }

  @Test
  func `adds experience across flights, day and night`() async throws {
    let flights = [
      Flight.fixture("one", day(2025, 5, 1)) {
        $0.counts.dayTakeoffs = 1
        $0.counts.dayLandings = 1
      },
      Flight.fixture("two", day(2025, 5, 3)) {
        $0.counts.nightTakeoffs = 2
        $0.counts.nightLandings = 2
      },
      Flight.fixture("a", day(2025, 5, 4)) { $0.carryPassenger() }
    ]
    #expect(try await flagged(flights).isEmpty)
  }

  @Test
  func `counts the 90th day back and not the 91st`() async throws {
    let subject = Flight.fixture("a", day(2025, 6, 15)) { $0.carryPassenger() }
    #expect(try await flagged([.landings("lap", day(2025, 3, 17, hour: 0)), subject]).isEmpty)
    #expect(try await flagged([.landings("lap", day(2025, 3, 16, hour: 23)), subject]) == ["a"])
  }

  @Test
  func `ignores flights without passengers, dual received and copilot flights`() async throws {
    #expect(
      try await flagged([
        .fixture("alone", day(2025, 5, 1)),
        .fixture("dual", day(2025, 5, 2)) {
          $0.carryPassenger()
          $0.times.dualReceived = 60
        },
        .fixture("sic", day(2025, 5, 3)) {
          $0.carryPassenger()
          $0.times.PIC = 0
        }
      ]).isEmpty
    )
  }

  @Test
  func `does not count experience in another class`() async throws {
    let flights = [
      Flight.landings("twin", day(2025, 5, 1), in: .twin),
      .fixture("a", day(2025, 5, 2)) { $0.carryPassenger() }
    ]
    #expect(try await flagged(flights) == ["a"])
  }

  @Test
  func `requires full-stop landings in a tailwheel airplane`() async throws {
    let tailDragger = Flight.landings("lap", day(2025, 5, 1), in: .tailwheel) {
      $0.counts.fullStops = 2
    }
    let subject = Flight.fixture("a", day(2025, 5, 2), in: .tailwheel) { $0.carryPassenger() }
    #expect(try await flagged([tailDragger, subject]) == ["a"])

    let fullStops = Flight.landings("lap", day(2025, 5, 1), in: .tailwheel)
    #expect(try await flagged([fullStops, subject]).isEmpty)
  }

  @Test
  func `counts full flight simulator experience as the aircraft it represents`() async throws {
    let subject = Flight.fixture("a", day(2025, 5, 2)) { $0.carryPassenger() }
    let ffs = Flight.landings(
      "ffs",
      day(2025, 5, 1),
      in: .simulator(representing: "C172", device: .FFS)
    )
    let aatd = Flight.landings(
      "aatd",
      day(2025, 5, 1),
      in: .simulator(representing: "C172", device: .AATD)
    )

    #expect(try await flagged([ffs, subject]).isEmpty)
    #expect(try await flagged([aatd, subject]) == ["a"])
    #expect(
      try await flagged([aatd, subject]) {
        $0.aircraft["SIM-AATD"] = AircraftSettings(simulatorCredit: [.takeoffsAndLandings])
      }.isEmpty
    )
  }

  @Test
  func `does not judge a flight whose aircraft is unknown`() async throws {
    var flight = Flight.fixture("a", day(2025, 5, 2)) { $0.carryPassenger() }
    flight.aircraft = nil
    #expect(try await flagged([flight]).isEmpty)
  }
}

@Suite
struct `Night passenger currency rule` {
  private func nightFlight(_ id: String, _ date: Date, in aircraft: Aircraft = .cessna) -> Flight {
    .fixture(id, date, in: aircraft) {
      $0.counts.nightTakeoffs = 3
      $0.counts.nightLandings = 3
      $0[field: Scenario.roleKeys[.nightFullStops]!] = .integer(3)
    }
  }

  private func subject(in aircraft: Aircraft = .cessna, _ date: Date = day(2025, 6, 1)) -> Flight {
    .fixture("a", date, in: aircraft) {
      $0.carryPassenger()
      $0.times.night = 30
    }
  }

  @Test
  func `needs night takeoffs and night full stops`() async throws {
    var onlyTakeoffs = nightFlight("lap", day(2025, 5, 1))
    onlyTakeoffs[field: Scenario.roleKeys[.nightFullStops]!] = .integer(2)

    let enough = Scenario(flights: [nightFlight("lap", day(2025, 5, 1)), subject()])
    let short = Scenario(flights: [onlyTakeoffs, subject()])

    #expect(try await enough.flagged(by: .noNightPassengerCurrency).isEmpty)
    #expect(try await short.flagged(by: .noNightPassengerCurrency) == ["a"])
  }

  @Test
  func `applies only to night flights with passengers`() async throws {
    var day = subject()
    day.times.night = 0
    var alone = subject()
    alone.passengers = []

    #expect(
      try await Scenario(flights: [day, alone]).flagged(by: .noNightPassengerCurrency).isEmpty
    )
  }

  @Test
  func `requires night experience in tailwheel airplanes for a tailwheel airplane`() async throws {
    let scenario = Scenario(flights: [
      nightFlight("lap", day(2025, 5, 1), in: .cessna), subject(in: .tailwheel)
    ])
    #expect(try await scenario.flagged(by: .noNightPassengerCurrency) == ["a"])
  }

  @Test
  func `extends the lookback to six months for a high-time pilot of a multi-pilot turbine`()
    async throws
  {
    func scenario(in aircraft: Aircraft) -> Scenario {
      Scenario(flights: [
        .fixture("history", day(2020, 1, 1), in: aircraft) { $0.times.PIC = 1_500 * 60 },
        nightFlight("lap", day(2025, 2, 1), in: aircraft),
        .fixture("hours", day(2025, 5, 15), in: aircraft) { $0.times.PIC = 15 * 60 },
        subject(in: aircraft)
      ])
    }

    #expect(try await scenario(in: .airliner).flagged(by: .noNightPassengerCurrency).isEmpty)
    #expect(try await scenario(in: .jet).flagged(by: .noNightPassengerCurrency) == ["a"])
  }

  @Test
  func `withholds the extended lookback without the hours in type`() async throws {
    let scenario = Scenario(flights: [
      .fixture("history", day(2020, 1, 1), in: .airliner) { $0.times.PIC = 1_500 * 60 },
      nightFlight("lap", day(2025, 2, 1), in: .airliner),
      .fixture("hours", day(2025, 5, 15), in: .airliner) { $0.times.PIC = 14 * 60 },
      subject(in: .airliner)
    ])
    #expect(try await scenario.flagged(by: .noNightPassengerCurrency) == ["a"])
  }
}
