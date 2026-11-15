public import Foundation

/// The meaning a check needs a logbook field to have, such as “night full-stop landings”.
///
/// LogTen has no built-in field for several values the regulations depend on, so pilots record
/// them in custom fields with titles of their choosing. A ``FieldMapping`` says which field holds
/// each role in a given logbook; a check whose role is unmapped is skipped and says so.
public enum FieldRole: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
  /// Night takeoffs, for 14 CFR 61.57(b). Defaults to LogTen's built-in night takeoffs.
  case nightTakeoffs = "night_takeoffs"
  /// Night full-stop landings, for 14 CFR 61.57(b).
  case nightFullStops = "night_full_stops"
  /// Cross-country time that meets the ATP definition (14 CFR 61.159(a)(1)).
  case atpCrossCountry = "atp_cross_country"
  /// The safety pilot for simulated instrument flight (14 CFR 91.109(c)).
  case safetyPilot = "safety_pilot"
  /// The examiner on a practical test.
  case examiner
  /// A note marking a 14 CFR 61.58 pilot-in-command proficiency check.
  case proficiencyCheck = "proficiency_check"
  /// A note marking a practical test.
  case checkride
  /// A note marking a 14 CFR 61.31(k) night-vision-goggle proficiency check.
  case nightVisionGoggleProficiencyCheck = "night_vision_goggle_proficiency_check"
  /// A field marking intercepting and tracking courses, for 14 CFR 61.57(c)(1).
  case interceptingAndTracking = "intercepting_and_tracking"
  /// The aircraft type's ICAO type designator, when LogTen's type identifier is something else.
  case typeCode = "type_code"
  /// The simulator or training-device type (BATD, AATD, FTD or FFS).
  case simulatorType = "simulator_type"
  /// The category and class a simulator represents (ASEL, AMEL, …).
  case simulatorCategoryClass = "simulator_category_class"

  /// The entity whose field holds the role.
  public var entity: LogTenEntity {
    switch self {
      case .typeCode, .simulatorType, .simulatorCategoryClass: .aircraftType
      default: .flight
    }
  }

  /// The kinds of custom slot that can hold the role.
  public var acceptedValueKinds: Set<CustomFieldValueKind> {
    switch self {
      case .nightTakeoffs, .nightFullStops: [.count]
      case .atpCrossCountry: [.minutes]
      case .safetyPilot, .examiner: [.person]
      case .proficiencyCheck, .checkride, .nightVisionGoggleProficiencyCheck: [.text, .flag]
      case .interceptingAndTracking: [.text, .flag, .count]
      case .typeCode, .simulatorType, .simulatorCategoryClass: [.text]
    }
  }

  /// Whether a built-in LogTen field, not only a custom slot, can hold the role.
  public var acceptsBuiltInFields: Bool {
    switch self {
      case .nightTakeoffs, .interceptingAndTracking: true
      default: false
    }
  }

  /// The field that holds the role when the mapping doesn't name one.
  public var defaultKey: LogTenFieldKey? {
    self == .nightTakeoffs ? .flightNightTakeoffs : nil
  }

  /// Custom-field titles that conventionally hold the role, used to suggest a mapping.
  public var conventionalTitles: [String] {
    switch self {
      case .nightTakeoffs: ["Night Takeoffs", "Night T/O"]
      case .nightFullStops: ["Night Full Stops", "Night Full Stop Landings", "Night FS"]
      case .atpCrossCountry: ["ATP XC", "ATP Cross Country", "ATP Cross-Country"]
      case .safetyPilot: ["Safety Pilot"]
      case .examiner: ["Examiner"]
      case .proficiencyCheck: ["FAR 61.58", "61.58", "61.58 Check", "PIC Proficiency Check"]
      case .checkride: ["Checkride", "Check Ride", "Practical Test"]
      case .nightVisionGoggleProficiencyCheck: ["FAR 61.31(k)", "61.31(k)", "NVG Proficiency Check"]
      case .interceptingAndTracking: ["Intercept/Tracking", "Intercepting and Tracking", "Tracking"]
      case .typeCode: ["Type Code", "ICAO Type"]
      case .simulatorType: ["Sim Type", "Simulator Type"]
      case .simulatorCategoryClass: ["Sim A/C Cat", "Sim Category", "Simulator Category"]
    }
  }

  /// Whether a field can hold this role.
  public func accepts(_ key: LogTenFieldKey) -> Bool {
    guard key.entity == entity else { return false }
    guard let slot = key.customSlot else { return acceptsBuiltInFields }
    return acceptedValueKinds.contains(slot.kind.valueKind)
  }
}

/// Which logbook field holds each ``FieldRole`` in one logbook.
public struct FieldMapping: Hashable, Codable, Sendable {
  private var assignments: [FieldRole: LogTenFieldKey]

  /// Roles with no field, explicit or default.
  public var unmappedRoles: [FieldRole] { FieldRole.allCases.filter { self[$0] == nil } }

  /// Creates a mapping in which only roles with a ``FieldRole/defaultKey`` are mapped.
  public init() {
    assignments = [:]
  }

  /**
   Suggests a mapping from the logbook's custom-field titles.

   A role is assigned when exactly one compatible field's title matches one of the role's
   ``FieldRole/conventionalTitles``, ignoring case, spaces and punctuation.

   - Parameter definitions: The logbook's custom fields.
   - Returns: The suggested mapping.
   */
  public static func suggested(for definitions: [CustomFieldDefinition]) -> Self {
    var mapping = Self()
    for role in FieldRole.allCases {
      let titles = Set(role.conventionalTitles.map(normalize))
      let matches = definitions.filter {
        role.accepts($0.key) && titles.contains(normalize($0.title))
      }
      if matches.count == 1 { mapping.assignments[role] = matches[0].key }
    }
    return mapping
  }

  private static func normalize(_ title: String) -> String {
    String(title.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
  }

  /// Assigns a field to a role, or restores the role's default with `nil`.
  ///
  /// - Throws: ``FieldMappingError/incompatibleField(_:role:)`` if the field can't hold the
  ///   role.
  public mutating func assign(_ key: LogTenFieldKey?, to role: FieldRole) throws(FieldMappingError)
  {
    if let key, !role.accepts(key) { throw .incompatibleField(key, role: role) }
    assignments[role] = key
  }

  /// The field that holds a role, or `nil` if the role is unmapped.
  public subscript(role: FieldRole) -> LogTenFieldKey? { assignments[role] ?? role.defaultKey }
}

/// An error assigning a field to a ``FieldRole``.
public enum FieldMappingError: Error, Equatable {
  /// The field is on the wrong entity or holds the wrong kind of value for the role.
  case incompatibleField(_ key: LogTenFieldKey, role: FieldRole)
}

extension FieldMappingError: LocalizedError {
  public var errorDescription: String? {
    String(localized: "Couldn’t assign the field.", bundle: .module)
  }

  public var failureReason: String? {
    switch self {
      case let .incompatibleField(key, role):
        String(
          localized: "The field “\(key.rawValue)” can’t hold “\(role.rawValue)”.",
          bundle: .module
        )
    }
  }
}

/// A custom field as the logbook defines it: its slot and the title the user gave it.
public struct CustomFieldDefinition: Hashable, Codable, Sendable {
  /// The slot's key.
  public var key: LogTenFieldKey

  /// The title LogTen shows for the field.
  public var title: String

  /// LogTen's default title for the slot, such as “Custom 1”.
  public var defaultTitle: String?

  /// Whether the field is enabled in LogTen, if LogTen records it.
  public var isEnabled: Bool?

  /// The slot the key addresses.
  public var slot: CustomFieldSlot? { key.customSlot }

  /// Whether the user has renamed the field from its default title.
  public var isRenamed: Bool { defaultTitle.map { $0 != title } ?? true }

  /// Creates a custom-field definition.
  public init(
    key: LogTenFieldKey,
    title: String,
    defaultTitle: String? = nil,
    isEnabled: Bool? = nil
  ) {
    self.key = key
    self.title = title
    self.defaultTitle = defaultTitle
    self.isEnabled = isEnabled
  }
}
