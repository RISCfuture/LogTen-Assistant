import Foundation
import LogbookModel
import Testing

@testable import LogTen_Assistant

struct LogbookFormatTests {
  private static let departure = Date(timeIntervalSince1970: 1_793_889_120)  // 2026-11-05 14:32Z
  private static let pacific = TimeZone(identifier: "America/Los_Angeles")!

  @Test
  func formatsClockTimesInTheGivenZoneOnA24HourClock() {
    #expect(LogbookFormat.clockTime(Self.departure, in: .gmt) == "14:32")
    #expect(LogbookFormat.clockTime(Self.departure, in: Self.pacific) == "06:32")
  }

  @Test
  func formatsZuluTimeWithItsUTCDay() {
    #expect(LogbookFormat.zuluTime(Self.departure) == "Nov 5, 14:32Z")
  }

  @Test(
    "A route shows both ends, a dash for a missing end, or nothing",
    arguments: [
      (Place.named("PAO"), Place.named("SQL"), "PAO → SQL"),
      (Place.named("PAO"), nil, "PAO → —"),
      (nil, Place.named("SQL"), "— → SQL"),
      (nil, nil, nil)
    ]
  )
  func formatsRoute(from: Place?, to: Place?, expected: String?) {
    let flight = Flight(id: RecordID(rawValue: "flight"), date: Self.departure, from: from, to: to)
    #expect(LogbookFormat.route(of: flight) == expected)
  }

  @Test(
    "Field values read as text only when set, unless explicit",
    arguments: [
      (FieldValue.null, CustomFieldValueKind.text, false, String?.none),
      (.text(""), .text, false, nil),
      (.text("Checkride"), .text, false, "Checkride"),
      (.integer(0), .count, false, nil),
      (.integer(0), .count, true, "0"),
      (.integer(-3), .count, false, nil),
      (.integer(90), .minutes, false, "1.5 hr"),
      (.boolean(false), .flag, false, nil),
      (.boolean(false), .flag, true, "No"),
      (.boolean(true), .flag, false, "Yes")
    ]
  )
  func formatsFieldValue(
    value: FieldValue,
    kind: CustomFieldValueKind,
    explicit: Bool,
    expected: String?
  ) {
    #expect(LogbookFormat.value(value, as: kind, explicit: explicit) == expected)
  }
}

extension Place {
  fileprivate static func named(_ identifier: String) -> Place {
    Place(
      id: RecordID(rawValue: "place-\(identifier)"),
      identifier: identifier,
      name: identifier,
      latitudeDeg: 0,
      longitudeDeg: 0
    )
  }
}
