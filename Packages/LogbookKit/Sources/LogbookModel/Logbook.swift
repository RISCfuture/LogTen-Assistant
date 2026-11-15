public import Foundation

/// The contents of one logbook snapshot.
public struct Logbook: Hashable, Codable, Sendable {
  /// Which logbook the snapshot came from.
  public var identity: LogbookIdentity

  /// Every entry, in date order.
  public var flights: [Flight]

  /// Every aircraft, by registration.
  public var aircraft: [Aircraft]

  /// Every person.
  public var people: [Person]

  /// Every place.
  public var places: [Place]

  /// The custom fields and the titles the user gave them.
  public var customFields: [CustomFieldDefinition]

  /// The logbook's groups and smart groups.
  public var groups: [LogbookGroup]

  /// A content hash of each flight, aircraft, aircraft type, person and place, for detecting
  /// records that changed between snapshots.
  public var fingerprints: [RecordID: RecordFingerprint]

  /// Creates a logbook.
  public init(
    identity: LogbookIdentity,
    flights: [Flight] = [],
    aircraft: [Aircraft] = [],
    people: [Person] = [],
    places: [Place] = [],
    customFields: [CustomFieldDefinition] = [],
    groups: [LogbookGroup] = [],
    fingerprints: [RecordID: RecordFingerprint] = [:]
  ) {
    self.identity = identity
    self.flights = flights
    self.aircraft = aircraft
    self.people = people
    self.places = places
    self.customFields = customFields
    self.groups = groups
    self.fingerprints = fingerprints
  }

  /// The custom field defined for a key, if any.
  public func customField(for key: LogTenFieldKey) -> CustomFieldDefinition? {
    customFields.first { $0.key == key }
  }
}

/// Identifies a LogTen logbook across snapshots.
public struct LogbookIdentity: Hashable, Codable, Sendable {
  /// The Core Data store UUID (`NSStoreUUID`), which is fixed for the life of the store.
  public var storeUUID: UUID

  /// The model version identifiers recorded in the store.
  public var modelVersionIdentifiers: [String]

  /// Creates a logbook identity.
  public init(storeUUID: UUID, modelVersionIdentifiers: [String] = []) {
    self.storeUUID = storeUUID
    self.modelVersionIdentifiers = modelVersionIdentifiers
  }
}

/// A SHA-256 hash of a record's stored values and relationships.
///
/// Two snapshots give a record the same fingerprint exactly when none of its attributes or
/// relationships changed.
public struct RecordFingerprint: RawRepresentable, Hashable, Codable, Sendable,
  CustomStringConvertible
{
  public let rawValue: String

  public var description: String { rawValue }

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

/// A LogTen group of flights: a folder, a manual group, or a smart group defined by criteria.
public struct LogbookGroup: Identifiable, Hashable, Codable, Sendable {
  /// The record identifier.
  public var id: RecordID

  /// The group's name.
  public var name: String

  /// LogTen's group type code.
  public var type: Int?

  /// The parent group, if the group is nested.
  public var parentID: RecordID?

  /// The `NSPredicate` format string LogTen stored for the group, if any.
  public var predicateFormat: String?

  /// Whether the group matches flights satisfying any criterion rather than all of them.
  public var matchesAnyCriterion: Bool

  /// The smart-group criteria, in the order LogTen stores them.
  public var criteria: [SmartGroupCriterion]

  /// Flights explicitly placed in the group.
  public var memberFlightIDs: [RecordID]

  /// Whether membership is computed from a predicate or criteria rather than assigned.
  public var isSmart: Bool { predicateFormat != nil || !criteria.isEmpty }

  /// Creates a group.
  public init(
    id: RecordID,
    name: String,
    type: Int? = nil,
    parentID: RecordID? = nil,
    predicateFormat: String? = nil,
    matchesAnyCriterion: Bool = false,
    criteria: [SmartGroupCriterion] = [],
    memberFlightIDs: [RecordID] = []
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.parentID = parentID
    self.predicateFormat = predicateFormat
    self.matchesAnyCriterion = matchesAnyCriterion
    self.criteria = criteria
    self.memberFlightIDs = memberFlightIDs
  }
}

/// One criterion of a LogTen smart group, as stored.
///
/// LogTen keeps a criterion's comparison value in whichever of several typed attributes suits
/// the field searched; the others are `nil`.
public struct SmartGroupCriterion: Hashable, Codable, Sendable {
  /// The customization key of the field searched, such as `flight_totalTime`.
  public var searchKey: String?

  /// The customization key of the comparison operator.
  public var searchOperator: String?

  /// The customization key of the search category.
  public var searchCategory: String?

  /// LogTen's criterion type code.
  public var type: Int?

  /// LogTen's evaluation type code.
  public var evaluationType: Int?

  /// The comparison value, for text fields.
  public var stringValue: String?
  /// The comparison value, for integer fields.
  public var integerValue: Int?
  /// The comparison value, for floating-point fields.
  public var numberValue: Double?
  /// The comparison value, for Boolean fields.
  public var booleanValue: Bool?
  /// The comparison value, for date fields.
  public var dateValue: Date?
  /// The comparison count, for criteria that count occurrences.
  public var count: Int?

  /// Creates a criterion.
  public init(
    searchKey: String? = nil,
    searchOperator: String? = nil,
    searchCategory: String? = nil,
    type: Int? = nil,
    evaluationType: Int? = nil,
    stringValue: String? = nil,
    integerValue: Int? = nil,
    numberValue: Double? = nil,
    booleanValue: Bool? = nil,
    dateValue: Date? = nil,
    count: Int? = nil
  ) {
    self.searchKey = searchKey
    self.searchOperator = searchOperator
    self.searchCategory = searchCategory
    self.type = type
    self.evaluationType = evaluationType
    self.stringValue = stringValue
    self.integerValue = integerValue
    self.numberValue = numberValue
    self.booleanValue = booleanValue
    self.dateValue = dateValue
    self.count = count
  }
}
