import Foundation
import LogbookModel
import Testing

@Suite
struct `Flight field access` {
  @Test
  func `reads and writes typed fields by key`() {
    var flight = Flight.blank
    flight[field: .flightNight] = .integer(42)
    flight[field: .flightReview] = .boolean(true)
    flight[field: .flightRemarks] = .text("Practice approaches")

    #expect(flight.times.night == 42)
    #expect(flight.isFlightReview)
    #expect(flight.remarks == "Practice approaches")
    #expect(flight[field: .flightNight] == .integer(42))
  }

  @Test
  func `treats null as zero, false or absent for typed fields`() {
    var flight = Flight.blank
    flight.times.night = 42
    flight.remarks = "Text"
    flight[field: .flightNight] = .null
    flight[field: .flightRemarks] = .null

    #expect(flight.times.night == 0)
    #expect(flight.remarks == nil)
    #expect(flight[field: .flightRemarks] == .null)
  }

  @Test
  func `keeps custom slots and other attributes apart`() throws {
    var flight = Flight.blank
    let customTime = LogTenFieldKey.custom(.flightTime, 7)
    let touchAndGoes = try #require(LogTenFieldKey(rawValue: "flight_touchAndGoes"))
    flight[field: customTime] = .integer(90)
    flight[field: touchAndGoes] = .integer(3)

    #expect(flight.customValues == [customTime: .integer(90)])
    #expect(flight.otherValues == [touchAndGoes: .integer(3)])

    flight[field: customTime] = .null
    #expect(flight.customValues.isEmpty)
    #expect(flight[field: customTime] == .null)
  }
}

@Suite
struct `Role access` {
  @Test
  func `distinguishes an unmapped role from an unset field`() throws {
    var mapping = FieldMapping()
    let flight = Flight.blank
    #expect(flight.count(for: .nightFullStops, in: mapping) == nil)

    try mapping.assign(.custom(.flightLanding, 5), to: .nightFullStops)
    #expect(flight.count(for: .nightFullStops, in: mapping) == 0)
  }

  @Test
  func `finds the person in a custom crew role`() throws {
    var mapping = FieldMapping()
    try mapping.assign(.custom(.flightCrew, 2), to: .safetyPilot)
    let safetyPilot = Person(id: RecordID(rawValue: "P2"), name: "Sam Safety")
    let flight = Flight(
      id: RecordID(rawValue: "F1"),
      date: .now,
      crew: FlightCrew(custom: [2: safetyPilot])
    )
    #expect(flight.person(for: .safetyPilot, in: mapping) == safetyPilot)
    #expect(flight.person(for: .examiner, in: mapping) == nil)
  }

  @Test
  func `falls back to LogTen's type identifier without a type-code field`() throws {
    var mapping = FieldMapping()
    let typeCodeKey = LogTenFieldKey.custom(.aircraftTypeAttribute, 4)
    let type = AircraftType(
      id: RecordID(rawValue: "T1"),
      type: "SR22 G6",
      customValues: [typeCodeKey: .text(" S22T ")]
    )
    #expect(type.typeCode(in: mapping) == "SR22 G6")

    try mapping.assign(typeCodeKey, to: .typeCode)
    #expect(type.typeCode(in: mapping) == "S22T")
  }
}

extension Flight {
  fileprivate static var blank: Self { Flight(id: RecordID(rawValue: "F1"), date: .now) }
}
