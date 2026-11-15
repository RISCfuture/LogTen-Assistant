import Foundation
import LogbookModel
import Testing

@Suite
struct `Field keys` {
  @Test(arguments: ["flight_totalTime", "aircraftType_customAttribute3", "place_icaoid"])
  func `parse well-formed LogTen attribute names`(_ name: String) throws {
    let key = try #require(LogTenFieldKey(rawValue: name))
    #expect(key.rawValue == name)
  }

  @Test(arguments: ["totalTime", "flight_", "logTen_uniqueID", "flight_total Time", "Flight_pic"])
  func `reject malformed or unknown-entity names`(_ name: String) {
    #expect(LogTenFieldKey(rawValue: name) == nil)
  }

  @Test
  func `identify the entity and attribute`() throws {
    let key = try #require(LogTenFieldKey(rawValue: "aircraftType_customAttribute3"))
    #expect(key.entity == .aircraftType)
    #expect(key.attributeName == "customAttribute3")
  }

  @Test
  func `identify custom slots within each kind's range`() throws {
    let slot = try #require(LogTenFieldKey(rawValue: "flight_customTime20")?.customSlot)
    #expect(slot.kind == .flightTime)
    #expect(slot.number == 20)
    #expect(LogTenFieldKey.flightTotalTime.customSlot == nil)
  }

  @Test(arguments: [
    "flight_customTime21", "flight_customTime07", "flight_customTime", "flight_customTime0",
    "flight_customTimeX", "person_customTime1"
  ])
  func `reject keys outside a slot's range or shape`(_ name: String) throws {
    let key = try #require(LogTenFieldKey(rawValue: name))
    #expect(key.customSlot == nil)
  }

  @Test
  func `distinguish aircraft and aircraft-type custom attributes`() throws {
    let aircraft = try #require(LogTenFieldKey(rawValue: "aircraft_customAttribute2")?.customSlot)
    let type = try #require(LogTenFieldKey(rawValue: "aircraftType_customAttribute2")?.customSlot)
    #expect(aircraft.kind == .aircraftAttribute)
    #expect(type.kind == .aircraftTypeAttribute)
  }

  @Test(arguments: CustomFieldKind.allCases)
  func `parse back every slot's own key`(_ kind: CustomFieldKind) {
    for slot in kind.allSlots {
      #expect(CustomFieldSlot(key: slot.key) == slot)
    }
  }

  @Test
  func `encode a slot as its key and refuse to decode any other key`() throws {
    let slot = CustomFieldSlot(kind: .flightCrew, number: 3)
    let encoded = try JSONEncoder().encode([slot])
    #expect(
      String(bytes: encoded, encoding: .utf8) == #"["flight_selectedCrewCustom3"]"#
    )
    #expect(try JSONDecoder().decode([CustomFieldSlot].self, from: encoded) == [slot])
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode([CustomFieldSlot].self, from: Data(#"["flight_totalTime"]"#.utf8))
    }
  }
}
