@testable import Audit
import Foundation
import LogbookModel
import Testing

@Suite
struct `Crew, simulator and record checks` {
  private typealias Fixtures = ConsistencyFixtures

  private static let owner = Person(id: "P-OWNER", name: "Owner", isMe: true)
  private static let other = Person(id: "P-OTHER", name: "Other")

  private static func secondInCommand(_ flight: inout Flight) {
    flight.times.PIC = 0
    flight.times.SIC = 60
  }

  private func rules(
    _ logbook: Logbook,
    owner: RecordID? = Self.owner.id
  ) -> [String] {
    var settings = Fixtures.settings
    settings.pilot.ownerPersonID = owner
    return ConsistencyAudit(settings: settings, options: .init()).run(on: logbook)
      .findings.map(\.rule.rawValue)
  }

  private func rules(_ flights: [Flight]) -> [String] {
    rules(Fixtures.logbook(flights))
  }

  @Test
  func `flags role time that disagrees with the owner's seat`() {
    let picFromSecondSeat = Fixtures.flight("F1", day: 1) {
      $0.times.PIC = 60
      $0.crew = FlightCrew(PIC: Self.other, SIC: Self.owner)
    }
    let sicFromCommandSeat = Fixtures.flight("F2", day: 2) {
      Self.secondInCommand(&$0)
      $0.crew = FlightCrew(PIC: Self.owner, SIC: Self.other)
    }
    let matching = Fixtures.flight("F3", day: 3) {
      $0.times.PIC = 60
      $0.crew = FlightCrew(PIC: Self.owner)
    }

    #expect(rules([picFromSecondSeat, sicFromCommandSeat, matching]) == ["crew_seat", "crew_seat"])
    #expect(rules(Fixtures.logbook([picFromSecondSeat]), owner: nil).isEmpty)
  }

  @Test
  func `flags a missing PIC only where the pilot usually names one`() {
    let named = (1...5).map { day in
      Fixtures.flight(RecordID(rawValue: "N\(day)"), day: day) {
        Self.secondInCommand(&$0)
        $0.crew = FlightCrew(PIC: Self.other)
      }
    }
    let unnamed = Fixtures.flight("U", day: 6, configure: Self.secondInCommand)
    let otherType = Fixtures.flight(
      "V",
      day: 7,
      aircraft: Fixtures.cirrus,
      configure: Self.secondInCommand
    )

    #expect(rules(named + [unnamed, otherType]) == ["pic_not_named"])
  }

  @Test
  func `flags instruction names that are missing or contradict the owner's role`() {
    let givenWithoutStudent =
      (1...5).map { day in
        Fixtures.flight(RecordID(rawValue: "G\(day)"), day: day) {
          $0.times.dualGiven = 60
          $0.crew = FlightCrew(student: Self.other)
        }
      } + [Fixtures.flight("G-missing", day: 6) { $0.times.dualGiven = 60 }]
    let ownerInstructsOwnLesson = Fixtures.flight("R", day: 7, aircraft: Fixtures.cirrus) {
      $0.times.dualReceived = 60
      $0.crew = FlightCrew(instructor: Self.owner)
    }

    #expect(
      rules(givenWithoutStudent + [ownerInstructsOwnLesson])
        == ["instruction_names", "instruction_names"]
    )
  }

  @Test
  func `flags solo time with an instructor named`() {
    let flight = Fixtures.flight("F1", day: 1) {
      $0.times.solo = 60
      $0.crew = FlightCrew(instructor: Self.other)
    }

    #expect(rules([flight]) == ["solo_with_instructor"])
  }

  @Test
  func `checks simulator time against the aircraft type's category`() {
    let simulatorTimeInAircraft = Fixtures.flight("F1", day: 1) { $0.times.simulator = 60 }
    let sessionWithoutSimulatorTime = Fixtures.flight("F2", day: 2, aircraft: Fixtures.simulator)
    let validSession = Fixtures.flight("F3", day: 3, aircraft: Fixtures.simulator) {
      $0.times.simulator = 60
    }

    #expect(
      rules([simulatorTimeInAircraft, sessionWithoutSimulatorTime, validSession])
        == ["simulator_session_time", "simulator_time_in_aircraft"]
    )
  }

  @Test
  func `reports incomplete aircraft types, aircraft, places and people by record`() {
    let unclassified = AircraftType(id: "T-BARE", type: " ")
    var logbook = Fixtures.logbook([])
    logbook.aircraft.append(Aircraft(id: "A-BARE", registration: "", type: nil))
    logbook.aircraft.append(Aircraft(id: "A-TYPED", registration: "N1", type: unclassified))
    logbook.places.append(Place(id: "PL-BARE", identifier: ""))
    logbook.people.append(Person(id: "P-BARE", name: ""))
    logbook.people.append(Self.other)

    #expect(
      rules(logbook).sorted() == [
        "aircraft_type_classification", "aircraft_type_identifier", "incomplete_aircraft",
        "incomplete_person", "incomplete_place"
      ]
    )
  }
}
