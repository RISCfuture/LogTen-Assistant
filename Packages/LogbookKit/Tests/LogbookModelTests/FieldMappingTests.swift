import Foundation
import LogbookModel
import Testing

@Suite
struct `Field mapping` {
  @Test
  func `suggests fields whose titles match a role's conventional titles`() {
    let mapping = FieldMapping.suggested(for: [
      CustomFieldDefinition(key: .custom(.flightLanding, 5), title: "night full-stops"),
      CustomFieldDefinition(key: .custom(.flightCrew, 1), title: "Safety Pilot"),
      CustomFieldDefinition(key: .custom(.flightNote, 1), title: "FAR 61.58"),
      CustomFieldDefinition(key: .custom(.aircraftTypeAttribute, 4), title: "Type Code")
    ])
    #expect(mapping[.nightFullStops] == .custom(.flightLanding, 5))
    #expect(mapping[.safetyPilot] == .custom(.flightCrew, 1))
    #expect(mapping[.proficiencyCheck] == .custom(.flightNote, 1))
    #expect(mapping[.typeCode] == .custom(.aircraftTypeAttribute, 4))
    #expect(mapping[.checkride] == nil)
  }

  @Test
  func `ignores matching titles on fields that hold the wrong kind of value`() {
    let mapping = FieldMapping.suggested(for: [
      CustomFieldDefinition(key: .custom(.flightNote, 3), title: "Safety Pilot"),
      CustomFieldDefinition(key: .custom(.flightTime, 2), title: "Night Full Stops")
    ])
    #expect(mapping[.safetyPilot] == nil)
    #expect(mapping[.nightFullStops] == nil)
  }

  @Test
  func `leaves a role unmapped when several fields match`() {
    let mapping = FieldMapping.suggested(for: [
      CustomFieldDefinition(key: .custom(.flightNote, 1), title: "Checkride"),
      CustomFieldDefinition(key: .custom(.flightNote, 2), title: "Check Ride")
    ])
    #expect(mapping[.checkride] == nil)
  }

  @Test
  func `maps night takeoffs to LogTen's built-in field by default`() throws {
    var mapping = FieldMapping()
    #expect(mapping[.nightTakeoffs] == .flightNightTakeoffs)

    try mapping.assign(.custom(.flightTakeoff, 1), to: .nightTakeoffs)
    #expect(mapping[.nightTakeoffs] == .custom(.flightTakeoff, 1))

    try mapping.assign(nil, to: .nightTakeoffs)
    #expect(mapping[.nightTakeoffs] == .flightNightTakeoffs)
  }

  @Test
  func `rejects a field that can't hold the role`() {
    var mapping = FieldMapping()
    #expect(throws: FieldMappingError.incompatibleField(.flightTotalTime, role: .safetyPilot)) {
      try mapping.assign(.flightTotalTime, to: .safetyPilot)
    }
    #expect(throws: FieldMappingError.self) {
      try mapping.assign(.custom(.aircraftTypeAttribute, 1), to: .checkride)
    }
  }

  @Test
  func `stores settings as readable JSON that decodes to the same value`() throws {
    var settings = LogbookSettings()
    try settings.fieldMapping.assign(.custom(.flightLanding, 5), to: .nightFullStops)
    settings.aircraft["N300DG"] = AircraftSettings(
      icaoAddress: ICAOAddress(hex: "A3F2C1"),
      requiresProficiencyCheck: true
    )
    settings.rules.customRules = [
      CustomRule(
        id: "night_within_total",
        kind: .subset,
        field: .flightNight,
        other: .flightTotalTime
      )
    ]

    let json = try JSONEncoder().encode(settings)
    let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
    let mapping = try #require(object["fieldMapping"] as? [String: Any])
    let assignments = try #require(mapping["assignments"] as? [String: String])
    let aircraft = try #require(object["aircraft"] as? [String: [String: Any]])

    #expect(assignments == ["night_full_stops": "flight_customLanding5"])
    #expect(aircraft["N300DG"]?["icaoAddress"] as? String == "a3f2c1")
    #expect(try JSONDecoder().decode(LogbookSettings.self, from: json) == settings)
  }
}
