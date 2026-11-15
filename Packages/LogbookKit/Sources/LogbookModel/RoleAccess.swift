import Foundation

extension Flight {
  /**
   The value of the field that holds a role.

   - Parameters:
     - role: A flight role.
     - mapping: The logbook's field mapping.
   - Returns: The value, ``FieldValue/null`` if the field is unset, or `nil` if the role is
     unmapped.
   */
  public func value(for role: FieldRole, in mapping: FieldMapping) -> FieldValue? {
    guard let key = mapping[role], key.entity == .flight else { return nil }
    return self[field: key]
  }

  /// The count in the field that holds a role, zero if unset, or `nil` if the role is unmapped.
  public func count(for role: FieldRole, in mapping: FieldMapping) -> UInt? {
    value(for: role, in: mapping).map { $0.unsignedInteger ?? 0 }
  }

  /// The minutes in the field that holds a role, zero if unset, or `nil` if the role is
  /// unmapped.
  public func minutes(for role: FieldRole, in mapping: FieldMapping) -> UInt? {
    count(for: role, in: mapping)
  }

  /// Whether the field that holds a role is set, or `nil` if the role is unmapped.
  public func isMarked(_ role: FieldRole, in mapping: FieldMapping) -> Bool? {
    value(for: role, in: mapping)?.isSet
  }

  /// The person in the custom crew role that holds a role, or `nil` if there is none or the
  /// role is unmapped.
  public func person(for role: FieldRole, in mapping: FieldMapping) -> Person? {
    guard let slot = mapping[role]?.customSlot, slot.kind == .flightCrew else { return nil }
    return crew.custom[slot.number]
  }
}

extension AircraftType {
  /// The ICAO type designator: the ``FieldRole/typeCode`` field if mapped and set, otherwise
  /// LogTen's type identifier.
  public func typeCode(in mapping: FieldMapping) -> String {
    text(for: .typeCode, in: mapping) ?? type
  }

  /// The simulator type recorded in the ``FieldRole/simulatorType`` field.
  public func simulatorType(in mapping: FieldMapping) -> SimulatorType? {
    text(for: .simulatorType, in: mapping).flatMap(SimulatorType.init)
  }

  /// The represented category and class recorded in the ``FieldRole/simulatorCategoryClass``
  /// field.
  public func simulatorCategoryClass(in mapping: FieldMapping) -> SimulatorCategoryClass? {
    text(for: .simulatorCategoryClass, in: mapping).flatMap(SimulatorCategoryClass.init)
  }

  /// The trimmed, non-empty text in the field that holds a role.
  public func text(for role: FieldRole, in mapping: FieldMapping) -> String? {
    guard let key = mapping[role], key.entity == .aircraftType,
      let text = customValues[key]?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    else { return nil }
    return text
  }
}
