import Corrections
import Foundation
import LogbookModel
import Testing

@Suite
struct `Import packages` {
  /// The metadata cleanup-logten's packages carried.
  private static let cleanupMetadata = ImportPackageMetadata(
    application: "LogTen Audit",
    version: "0.1.0"
  )

  private static func utc(_ text: String) throws -> Date {
    try Date(text, strategy: .iso8601)
  }

  private func change(
    _ key: String,
    _ field: LogTenFieldKey,
    old: FieldValue = .null,
    _ new: FieldValue
  ) -> FieldChange {
    FieldChange(flightKey: key, recordID: RecordID(rawValue: key), field: field, old: old, new: new)
  }

  @Test
  func `match cleanup-logten's airborne-time package byte for byte`() throws {
    let batch = CorrectionBatch(changes: [
      change("KEY-1", .flightTakeoffTime, .date(try Self.utc("2026-10-20T15:30:00Z"))),
      change("KEY-1", .flightLandingTime, .date(try Self.utc("2026-10-20T16:45:00Z")))
    ])
    let package = try ImportPackage(batch: batch, metadata: Self.cleanupMetadata)

    #expect(
      package.json
        == #"{"metadata":{"application":"LogTen Audit","version":"0.1.0","timesAreZulu":true,"shouldApplyAutoFillTimes":false},"entities":[{"entity_name":"Flight","flight_key":"KEY-1","flight_takeoffTime":1792510200.0,"flight_landingTime":1792514700.0}]}"#
    )
    #expect(
      package.url.absoluteString
        == "logten://v2/addEntities?package=%7B%22metadata%22%3A%7B%22application%22%3A%22LogTen%20Audit%22%2C%22version%22%3A%220.1.0%22%2C%22timesAreZulu%22%3Atrue%2C%22shouldApplyAutoFillTimes%22%3Afalse%7D%2C%22entities%22%3A%5B%7B%22entity_name%22%3A%22Flight%22%2C%22flight_key%22%3A%22KEY-1%22%2C%22flight_takeoffTime%22%3A1792510200.0%2C%22flight_landingTime%22%3A1792514700.0%7D%5D%7D"
    )
  }

  @Test
  func `write durations, counts, text and dates as cleanup-logten's evidence packages did`() throws
  {
    let batch = CorrectionBatch(changes: [
      change("KEY-2", .flightTotalTime, old: .integer(60), .integer(64)),
      change("KEY-2", .flightFullStops, .integer(2)),
      change("KEY-2", .flightRemarks, .text("Café “night” #3")),
      change("KEY-2", .flightDate, .date(try Self.utc("2026-10-20T00:00:00Z")))
    ])
    let package = try ImportPackage(batch: batch, metadata: Self.cleanupMetadata)

    #expect(
      package.url.absoluteString
        == "logten://v2/addEntities?package=%7B%22metadata%22%3A%7B%22application%22%3A%22LogTen%20Audit%22%2C%22version%22%3A%220.1.0%22%2C%22timesAreZulu%22%3Atrue%2C%22shouldApplyAutoFillTimes%22%3Afalse%7D%2C%22entities%22%3A%5B%7B%22entity_name%22%3A%22Flight%22%2C%22flight_key%22%3A%22KEY-2%22%2C%22flight_totalTime%22%3A%221%3A04%22%2C%22flight_fullStops%22%3A2%2C%22flight_remarks%22%3A%22Caf%5Cu00e9%20%5Cu201cnight%5Cu201d%20%233%22%2C%22flight_flightDate%22%3A1792454400%7D%5D%7D"
    )
  }

  @Test
  func `clears fields with null and groups changes by flight`() throws {
    let batch = CorrectionBatch(changes: [
      change("A", .custom(.flightTime, 3), old: .integer(30), .null),
      change("B", .flightNight, .integer(5))
    ])
    let package = try ImportPackage(batch: batch, metadata: .init(version: "1.0"))

    #expect(package.entities.map(\.flightKey) == ["A", "B"])
    #expect(
      package.json.contains(#"{"entity_name":"Flight","flight_key":"A","flight_customTime3":null}"#)
    )
    #expect(package.json.contains(#""flight_night":"0:05""#))
  }

  @Test
  func `refuses fields outside the allowlist and repeated fields`() {
    #expect(throws: CorrectionError.fieldNotImportable(.flightGround)) {
      try ImportPackage(
        batch: CorrectionBatch(changes: [change("A", .flightGround, .integer(5))]),
        metadata: .init(version: "1.0")
      )
    }
    #expect(throws: CorrectionError.conflictingChanges(RecordID(rawValue: "A"), .flightNight)) {
      try ImportPackage(
        batch: CorrectionBatch(changes: [
          change("A", .flightNight, .integer(5)), change("A", .flightNight, .integer(6))
        ]),
        metadata: .init(version: "1.0")
      )
    }
    #expect(throws: CorrectionError.unsuitableValue(.flightNight, .text("five"))) {
      try ImportPackage(
        batch: CorrectionBatch(changes: [change("A", .flightNight, .text("five"))]),
        metadata: .init(version: "1.0")
      )
    }
  }

  @Test(
    arguments: [
      (LogTenFieldKey.flightNight, FieldValue.integer(0), JSONValue.string("0:00")),
      (.flightNight, .integer(-5), nil),
      (.flightFullStops, .integer(-1), nil),
      (.flightHobbsStart, .number(1233), .integer(1233)),
      (.flightHobbsStart, .number(1233.4), .double(1233.4)),
      (.flightHobbsStart, .integer(7), .integer(7)),
      (.flightRemarks, .integer(7), nil),
      (.flightTakeoffTime, .text("noon"), nil),
      (.flightDate, .date(Date(timeIntervalSince1970: 1_792_454_400.5)), .double(1_792_454_400.5))
    ]
  )
  func `encode values by field type and refuse unsuitable ones`(
    field: LogTenFieldKey,
    value: FieldValue,
    expected: JSONValue?
  ) {
    #expect(ImportField.packageValue(value, for: field) == expected)
  }
}
