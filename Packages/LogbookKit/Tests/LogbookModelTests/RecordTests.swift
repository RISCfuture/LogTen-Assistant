import Foundation
import LogbookModel
import Testing

@Suite
struct `Flight components` {
  private static func person(_ id: String) -> Person {
    Person(id: RecordID(rawValue: id), name: id)
  }

  @Test
  func `list each crew member once, in position order`() {
    let crew = FlightCrew(
      PIC: Self.person("A"),
      SIC: Self.person("B"),
      student: Self.person("C"),
      observers: [Self.person("D"), Self.person("A")],
      flightAttendants: [Self.person("E")],
      custom: [4: Self.person("F"), 2: Self.person("B"), 3: Self.person("G")]
    )
    #expect(crew.everyone.map(\.id.rawValue) == ["A", "B", "C", "D", "E", "G", "F"])
  }
}
