import Foundation
import LogbookModel
import Testing

@Suite
struct `Field values` {
  @Test(arguments: [
    (FieldValue.null, false),
    (.integer(0), false),
    (.integer(-1), true),
    (.number(0), false),
    (.number(0.5), true),
    (.boolean(false), false),
    (.text("  \n"), false),
    (.text(" x "), true),
    (.date(Date(timeIntervalSinceReferenceDate: 0)), true)
  ])
  func `are set the way LogTen shows them`(value: FieldValue, isSet: Bool) {
    #expect(value.isSet == isSet)
  }

  @Test
  func `give an unsigned integer only for non-negative integers`() {
    #expect(FieldValue.number(7.5).unsignedInteger == nil)
    #expect(FieldValue.integer(-3).unsignedInteger == nil)
    #expect(FieldValue.integer(3).unsignedInteger == 3)
  }

  @Test
  func `express dates as seconds since the reference date in JSON`() {
    #expect(FieldValue.date(Date(timeIntervalSinceReferenceDate: 90)).jsonValue == .double(90))
    #expect(FieldValue.number(2).jsonValue == .double(2))
    #expect(FieldValue.integer(2).jsonValue == .integer(2))
  }

  @Test(arguments: [
    (FieldValue.null, #"{"type":"null"}"#),
    (.integer(-5), #"{"type":"integer","value":-5}"#),
    (.text("x"), #"{"type":"text","value":"x"}"#)
  ])
  func `persist as a tagged type and value`(value: FieldValue, json: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(String(bytes: try encoder.encode(value), encoding: .utf8) == json)
    #expect(try JSONDecoder().decode(FieldValue.self, from: Data(json.utf8)) == value)
  }

  @Test
  func `round-trip dates through their stored form`() throws {
    let value = FieldValue.date(Date(timeIntervalSinceReferenceDate: 12_345))
    #expect(try JSONDecoder().decode(FieldValue.self, from: JSONEncoder().encode(value)) == value)
  }
}

@Suite
struct `JSON values` {
  @Test
  func `decode each JSON type to its case`() throws {
    let decoded = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(#"{"a":[5,2.5,true,null,"s"]}"#.utf8)
    )
    #expect(decoded == ["a": [5, 2.5, true, nil, "s"]])
  }
}
