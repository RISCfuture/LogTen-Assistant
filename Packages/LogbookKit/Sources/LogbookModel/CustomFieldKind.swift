/// A family of numbered custom fields that LogTen lets the user title and enable.
///
/// Each kind is a key prefix plus a range of slot numbers: `flight_customTime` with slots 1–20
/// gives `flight_customTime1` through `flight_customTime20`.
public enum CustomFieldKind: String, CaseIterable, Codable, Sendable {
  /// Custom flight times, in minutes.
  case flightTime = "flight_customTime"
  /// Custom landing counts.
  case flightLanding = "flight_customLanding"
  /// Custom takeoff counts.
  case flightTakeoff = "flight_customTakeoff"
  /// Custom free-text notes.
  case flightNote = "flight_customNote"
  /// Custom operation counts.
  case flightOperation = "flight_customOp"
  /// Custom crew-capacity flags.
  case flightCapacity = "flight_customCapacity"
  /// Custom crew roles, each naming a person.
  case flightCrew = "flight_selectedCrewCustom"
  /// Custom aircraft flags.
  case aircraftAttribute = "aircraft_customAttribute"
  /// Custom aircraft text.
  case aircraftText = "aircraft_customText"
  /// Custom aircraft-type text.
  case aircraftTypeAttribute = "aircraftType_customAttribute"
  /// Custom place text.
  case placeAttribute = "place_customAttribute"
  /// Custom person text.
  case personAttribute = "person_customAttribute"

  /// The slot numbers LogTen provides for this kind.
  public var slots: ClosedRange<UInt> {
    switch self {
      case .flightTime, .flightOperation, .flightCapacity: 1...20
      case .flightLanding, .flightTakeoff, .flightNote, .flightCrew, .placeAttribute: 1...10
      case .aircraftText: 1...8
      case .aircraftAttribute, .aircraftTypeAttribute, .personAttribute: 1...5
    }
  }

  /// The kind of value each slot holds.
  public var valueKind: CustomFieldValueKind {
    switch self {
      case .flightTime: .minutes
      case .flightLanding, .flightTakeoff, .flightOperation: .count
      case .flightCapacity, .aircraftAttribute: .flag
      case .flightCrew: .person
      case .flightNote, .aircraftText, .aircraftTypeAttribute, .placeAttribute, .personAttribute:
        .text
    }
  }

  /// The entity that owns this kind's slots.
  public var entity: LogTenEntity {
    LogTenFieldKey(rawValue: rawValue + "1")!.entity
  }

  /// Every slot of this kind, in slot order.
  public var allSlots: [CustomFieldSlot] {
    slots.map { CustomFieldSlot(kind: self, number: $0) }
  }
}

/// The kind of value a custom field slot holds.
public enum CustomFieldValueKind: String, Codable, Sendable {
  /// A duration in whole minutes.
  case minutes
  /// A non-negative count.
  case count
  /// A Boolean flag.
  case flag
  /// Free text; LogTen treats any non-empty text as “set”.
  case text
  /// The name of a person in a crew role.
  case person
}

/// One numbered custom field, such as custom time 7.
public struct CustomFieldSlot: Hashable, Codable, Sendable {
  /// The kind of custom field.
  public let kind: CustomFieldKind

  /// The slot number within ``CustomFieldKind/slots``.
  public let number: UInt

  /// The LogTen key for this slot, such as `flight_customTime7`.
  public var key: LogTenFieldKey { LogTenFieldKey(rawValue: "\(kind.rawValue)\(number)")! }

  /// Creates a slot, trapping if `number` is outside the kind's range.
  public init(kind: CustomFieldKind, number: UInt) {
    precondition(kind.slots.contains(number), "\(kind.rawValue) has no slot \(number)")
    self.kind = kind
    self.number = number
  }

  public init(from decoder: any Decoder) throws {
    let key = try LogTenFieldKey(from: decoder)
    guard let slot = Self(key: key) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "\(key) is not a custom slot")
      )
    }
    self = slot
  }

  /// Identifies the custom slot a LogTen key addresses, if it addresses one.
  public init?(key: LogTenFieldKey) {
    for kind in CustomFieldKind.allCases where key.rawValue.hasPrefix(kind.rawValue) {
      let suffix = key.rawValue.dropFirst(kind.rawValue.count)
      guard let number = UInt(suffix), kind.slots.contains(number),
        suffix == String(number)
      else { continue }
      self.kind = kind
      self.number = number
      return
    }
    return nil
  }

  /// Encodes the slot as its LogTen key.
  public func encode(to encoder: any Encoder) throws {
    try key.encode(to: encoder)
  }
}
