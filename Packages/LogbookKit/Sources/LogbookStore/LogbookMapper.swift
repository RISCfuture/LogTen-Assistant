import CoreData
import ExceptionCatching
import Foundation
import LogbookModel

/// Maps the managed objects of one store into model values. Used only inside the reader's
/// context queue.
struct LogbookMapper {
  private static let passengerSlots = 1...20
  private static let approachSlots = 1...10
  private static let observerSlots = 1...2
  private static let reliefSlots = 1...4
  private static let flightAttendantSlots = 1...4
  private static let customizationKeyPrefixes = CustomFieldKind.allCases.map(\.rawValue)

  /// Flight relationships that describe membership or attachments rather than the entry itself,
  /// so they don't contribute to a flight's fingerprint.
  private static let unfingerprintedFlightRelationships: Set = [
    "flight_groups", "flight_certificates", "flight_expenseSet"
  ]

  let context: NSManagedObjectContext

  private static func utcYear(_ date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.component(.year, from: date)
  }

  func logbook(identity: LogbookIdentity, progress: ProgressTally.Report? = nil) throws
    -> Logbook
  {
    var fingerprints = [RecordID: RecordFingerprint]()
    let people = try records(of: "Person", fingerprints: &fingerprints) { object, values in
      person(object, values: values)
    }
    let places = try records(of: "Place", fingerprints: &fingerprints) { object, values in
      place(object, values: values)
    }
    let types = try records(of: "AircraftType", fingerprints: &fingerprints) { object, values in
      aircraftType(object, values: values)
    }
    let aircraft = try records(of: "Aircraft", fingerprints: &fingerprints) { object, values in
      self.aircraft(object, values: values, types: types)
    }
    let directory = RecordDirectory(
      people: people,
      places: places,
      types: types,
      aircraft: aircraft
    )
    let flights = try flights(
      directory: directory,
      fingerprints: &fingerprints,
      progress: progress
    )

    return Logbook(
      identity: identity,
      flights: flights,
      aircraft: aircraft.values.sorted { $0.registration < $1.registration },
      people: people.values.sorted { $0.name < $1.name },
      places: places.values.sorted { $0.identifier < $1.identifier },
      customFields: try customFieldDefinitions(),
      groups: try groups(),
      fingerprints: fingerprints
    )
  }

  func customFieldDefinitions() throws -> [CustomFieldDefinition] {
    var definitions = [LogTenFieldKey: CustomFieldDefinition]()
    for object in try fetch("LogTenCustomizationProperty") {
      guard let rawKey = object.string("logTenProperty_key"),
        Self.customizationKeyPrefixes.contains(where: rawKey.hasPrefix),
        let key = LogTenFieldKey(rawValue: rawKey), key.customSlot != nil,
        definitions[key] == nil
      else { continue }
      definitions[key] = CustomFieldDefinition(
        key: key,
        title: object.string("logTenCustomizationProperty_title") ?? "",
        defaultTitle: object.string("logTenCustomizationProperty_defaultTitle"),
        isEnabled: object.value(forKey: "logTenCustomizationProperty_enabled") as? Bool
      )
    }
    return definitions.values.sorted { $0.key < $1.key }
  }

  func flightIDs(matching format: String) throws -> [RecordID] {
    var result: Result<[NSManagedObject], any Error> = .success([])
    do {
      try ObjCExceptionCatcher.perform {
        let predicate = NSPredicate(format: format, argumentArray: nil)
        result = Result { try fetch("Flight", predicate: predicate) }
      }
    } catch {
      throw LogbookStoreError.invalidPredicate(format, reason: error.objCExceptionReason)
    }
    return try result.get().map(recordID).sorted()
  }

  // MARK: - Fetching

  private func fetch(
    _ entityName: String,
    predicate: NSPredicate? = nil,
    prefetching relationships: [String] = []
  ) throws -> [NSManagedObject] {
    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
    request.predicate = predicate
    request.includesSubentities = true
    request.returnsObjectsAsFaults = false
    request.relationshipKeyPathsForPrefetching = relationships
    return try context.fetch(request)
  }

  private func records<Record: Identifiable>(
    of entityName: String,
    fingerprints: inout [RecordID: RecordFingerprint],
    map: (NSManagedObject, ScalarValues) -> Record
  ) throws -> [NSManagedObjectID: Record] where Record.ID == RecordID {
    var records = [NSManagedObjectID: Record]()
    for object in try fetch(entityName) {
      let values = ScalarValues(object)
      let record = map(object, values)
      records[object.objectID] = record
      fingerprints[record.id] = fingerprint(of: object, values: values)
    }
    return records
  }

  // MARK: - Records

  private func recordID(_ object: NSManagedObject) -> RecordID {
    if let uniqueID = object.string("logTen_uniqueID"), !uniqueID.isEmpty {
      return RecordID(rawValue: uniqueID)
    }
    let primaryKey = object.objectID.uriRepresentation().lastPathComponent.dropFirst()
    return RecordID(primaryKey: Int64(primaryKey) ?? 0)
  }

  private func person(_ object: NSManagedObject, values: ScalarValues) -> Person {
    Person(
      id: recordID(object),
      name: values.text("person_name") ?? "",
      email: values.text("person_email"),
      firstName: values.text("person_firstName"),
      lastName: values.text("person_lastName"),
      personID: values.text("person_personID"),
      isMe: values.flag("person_isMe"),
      customValues: values.customValues
    )
  }

  private func place(_ object: NSManagedObject, values: ScalarValues) -> Place {
    Place(
      id: recordID(object),
      identifier: values.text("place_identifier") ?? "",
      ICAO: values.text("place_icaoid"),
      FAAID: values.text("place_faaId"),
      IATA: values.text("place_iataid"),
      name: values.text("place_name"),
      latitudeDeg: values.number("place_lat"),
      longitudeDeg: values.number("place_lon"),
      elevationFt: values.integer("place_elevation"),
      timeZoneIdentifier: values.text("place_timeZoneName"),
      customValues: values.customValues
    )
  }

  private func aircraftType(_ object: NSManagedObject, values: ScalarValues) -> AircraftType {
    AircraftType(
      id: recordID(object),
      type: values.text("aircraftType_type") ?? "",
      make: values.text("aircraftType_make"),
      model: values.text("aircraftType_model"),
      category: slotValue(object, "aircraftType_category"),
      aircraftClass: slotValue(object, "aircraftType_aircraftClass"),
      engineType: slotValue(object, "aircraftType_engineType"),
      isMultiPilot: values.flag("aircraftType_multiPilot"),
      customValues: values.customValues
    )
  }

  private func slotValue<Value: LogTenSlotValue>(_ object: NSManagedObject, _ relationship: String)
    -> Value?
  {
    guard let property = object.related(relationship) else { return nil }
    return Value.resolve(
      key: property.string("logTenProperty_key"),
      title: property.string("logTenCustomizationProperty_title")
    )
  }

  private func aircraft(
    _ object: NSManagedObject,
    values: ScalarValues,
    types: [NSManagedObjectID: AircraftType]
  ) -> Aircraft {
    Aircraft(
      id: recordID(object),
      registration: values.text("aircraft_aircraftID") ?? "",
      secondaryID: values.text("aircraft_secondaryID"),
      type: object.related("aircraft_aircraftType").flatMap { types[$0.objectID] },
      weightLbs: values.number("aircraft_weight"),
      year: values.date("aircraft_year").map(Self.utcYear),
      isComplex: values.flag("aircraft_complex"),
      isHighPerformance: values.flag("aircraft_highPerformance"),
      isPressurized: values.flag("aircraft_pressurized"),
      isTechnicallyAdvanced: values.flag("aircraft_technicallyAdvanced"),
      hasRetractableGear: values.flag("aircraft_undercarriageRetractable"),
      isAmphibious: values.flag("aircraft_undercarriageAmphib"),
      hasFloats: values.flag("aircraft_undercarriageFloats"),
      hasSkis: values.flag("aircraft_undercarriageSkis"),
      hasSkids: values.flag("aircraft_undercarriageSkids"),
      isTailwheel: values.flag("aircraft_tailwheel"),
      hasRadialEngine: values.flag("aircraft_radialEngine"),
      customValues: values.customValues
    )
  }

  // MARK: - Flights

  private func flights(
    directory: RecordDirectory,
    fingerprints: inout [RecordID: RecordFingerprint],
    progress: ProgressTally.Report?
  ) throws -> [Flight] {
    let objects = try fetch(
      "Flight",
      prefetching: [
        "flight_flightCrew", "flight_flightPassengers", "flight_flightApproaches",
        "flight_signature"
      ]
    )
    let approachObjects = try fetch("Approach")
    let approaches = Dictionary(
      uniqueKeysWithValues: approachObjects.map {
        ($0.objectID, approach($0, places: directory.places))
      }
    )
    var tally = ProgressTally(total: objects.count, report: progress)
    return objects.map { object in
      let values = ScalarValues(object)
      let flight = flight(object, values: values, directory: directory, approaches: approaches)
      fingerprints[flight.id] = flightFingerprint(of: object, values: values)
      tally.advance()
      return flight
    }
    .sorted { ($0.date, $0.events.out ?? $0.date) < ($1.date, $1.events.out ?? $1.date) }
  }

  private func flight(
    _ object: NSManagedObject,
    values: ScalarValues,
    directory: RecordDirectory,
    approaches: [NSManagedObjectID: Approach]
  ) -> Flight {
    var flight = Flight(
      id: recordID(object),
      date: values.date("flight_flightDate") ?? .distantPast
    )
    for (key, value) in values.fieldValues { flight[field: key] = value }

    flight.isSigned = object.related("flight_signature") != nil
    flight.aircraft = object.related("flight_aircraft").flatMap { directory.aircraft[$0.objectID] }
    if let type = object.related("flight_aircraftType").flatMap({ directory.types[$0.objectID] }) {
      flight.aircraft?.type = type
    }
    flight.from = object.related("flight_fromPlace").flatMap { directory.places[$0.objectID] }
    flight.to = object.related("flight_toPlace").flatMap { directory.places[$0.objectID] }
    if let crew = object.related("flight_flightCrew") {
      flight.crew = self.crew(crew, people: directory.people)
      for (number, person) in flight.crew.custom {
        flight[field: .custom(.flightCrew, number)] = .text(person.name)
      }
    }
    flight.passengers =
      object.related("flight_flightPassengers").map { passengers in
        Self.passengerSlots.compactMap { slot in
          passengers.related("flightPassengers_pax\(slot)").flatMap {
            directory.people[$0.objectID]
          }
        }
      } ?? []
    flight.approaches =
      object.related("flight_flightApproaches").map { container in
        Self.approachSlots.compactMap { slot in
          container.related("flightApproaches_approach\(slot)").flatMap { approaches[$0.objectID] }
        }
      } ?? []
    return flight
  }

  private func crew(_ object: NSManagedObject, people: [NSManagedObjectID: Person]) -> FlightCrew {
    func person(_ relationship: String) -> Person? {
      object.related(relationship).flatMap { people[$0.objectID] }
    }
    func positions(_ prefix: String, _ slots: ClosedRange<Int>) -> [Person] {
      slots.compactMap { person("\(prefix)\($0)") }
    }
    let customSlots = CustomFieldKind.flightCrew.slots
    return FlightCrew(
      PIC: person("flightCrew_PIC"),
      SIC: person("flightCrew_SIC"),
      instructor: person("flightCrew_instructor"),
      student: person("flightCrew_student"),
      flightEngineer: person("flightCrew_flightEngineer"),
      commander: person("flightCrew_commander"),
      purser: person("flightCrew_purser"),
      observers: positions("flightCrew_observer", Self.observerSlots),
      relief: positions("flightCrew_relief", Self.reliefSlots),
      flightAttendants: positions("flightCrew_flightAttendant", Self.flightAttendantSlots),
      custom: Dictionary(
        uniqueKeysWithValues: customSlots.compactMap { slot in
          person("flightCrew_custom\(slot)").map { (slot, $0) }
        }
      )
    )
  }

  private func approach(_ object: NSManagedObject, places: [NSManagedObjectID: Place]) -> Approach {
    let values = ScalarValues(object)
    return Approach(
      id: recordID(object),
      place: object.related("approach_place").flatMap { places[$0.objectID] },
      type: values.text("approach_type").flatMap(ApproachType.init(rawValue:)),
      runway: values.text("approach_comment"),
      count: values.integer("approach_quantity").map { UInt(max($0, 0)) } ?? 1,
      isNight: values.flag("approach_night"),
      isSimulated: values.flag("approach_simulated")
    )
  }

  // MARK: - Groups

  private func groups() throws -> [LogbookGroup] {
    try fetch("Group", prefetching: ["group_criteria", "group_flights"]).map { object in
      let values = ScalarValues(object)
      return LogbookGroup(
        id: recordID(object),
        name: values.text("group_name") ?? "",
        type: values.integer("group_type"),
        parentID: object.related("group_parent").map(recordID),
        predicateFormat: values.text("group_predicateString").flatMap { $0.isEmpty ? nil : $0 },
        matchesAnyCriterion: values.flag("group_criteriaShouldMatchAny"),
        criteria: object.relatedSet("group_criteria")
          .sorted {
            $0.objectID.uriRepresentation().absoluteString
              < $1.objectID.uriRepresentation().absoluteString
          }
          .map(criterion),
        memberFlightIDs: object.relatedSet("group_flights").map(recordID).sorted()
      )
    }
    .sorted { $0.name < $1.name }
  }

  private func criterion(_ object: NSManagedObject) -> SmartGroupCriterion {
    let values = ScalarValues(object)
    func key(_ relationship: String) -> String? {
      object.related(relationship)?.string("logTenProperty_key")
    }
    return SmartGroupCriterion(
      searchKey: key("smartGroupCriterion_searchKey"),
      searchOperator: key("smartGroupCriterion_searchOperator"),
      searchCategory: key("smartGroupCriterion_searchCategory"),
      type: values.integer("smartGroupCriterion_type"),
      evaluationType: values.integer("smartGroupCriterion_evaluationType"),
      stringValue: values.text("smartGroupCriterion_searchStringValue"),
      integerValue: values.integer("smartGroupCriterion_searchIntValue"),
      numberValue: values.number("smartGroupCriterion_searchFloatValue"),
      booleanValue: values.optionalFlag("smartGroupCriterion_searchBoolValue"),
      dateValue: values.date("smartGroupCriterion_searchDateValue"),
      count: values.integer("smartGroupCriterion_searchCount")
    )
  }

  // MARK: - Fingerprints

  private func fingerprint(of object: NSManagedObject, values: ScalarValues) -> RecordFingerprint {
    RecordFingerprint(
      rawValue: CanonicalJSON.sha256(of: [
        "attributes": values.json,
        "relationships": .object(toOneRelationshipIDs(of: object))
      ])
    )
  }

  private func flightFingerprint(of object: NSManagedObject, values: ScalarValues)
    -> RecordFingerprint
  {
    var relationships = toOneRelationshipIDs(
      of: object,
      excluding: Self.unfingerprintedFlightRelationships
    )
    for name in ["flight_flightCrew", "flight_flightPassengers"] {
      relationships[name] =
        object.related(name).map { .object(toOneRelationshipIDs(of: $0)) } ?? .null
    }
    relationships["flight_flightApproaches"] =
      object.related("flight_flightApproaches").map { container in
        .array(
          Self.approachSlots.map { slot in
            container.related("flightApproaches_approach\(slot)").map { approach in
              .object([
                "attributes": ScalarValues(approach).json,
                "relationships": .object(toOneRelationshipIDs(of: approach))
              ])
            } ?? .null
          }
        )
      } ?? .null
    relationships["flight_waypointPlaces"] = .array(
      object.relatedSet("flight_waypointPlaces").map { .string(recordID($0).rawValue) }.sorted {
        ($0.stringValue ?? "") < ($1.stringValue ?? "")
      }
    )
    return RecordFingerprint(
      rawValue: CanonicalJSON.sha256(of: [
        "attributes": values.json, "relationships": .object(relationships)
      ])
    )
  }

  private func toOneRelationshipIDs(
    of object: NSManagedObject,
    excluding excluded: Set<String> = []
  )
    -> [String: JSONValue]
  {
    var ids = [String: JSONValue]()
    for (name, relationship) in object.entity.relationshipsByName
    where !relationship.isToMany && !excluded.contains(name) {
      ids[name] = object.related(name).map { .string(recordID($0).rawValue) } ?? .null
    }
    return ids
  }
}

/// The records a flight refers to, by managed object ID.
private struct RecordDirectory {
  let people: [NSManagedObjectID: Person]
  let places: [NSManagedObjectID: Place]
  let types: [NSManagedObjectID: AircraftType]
  let aircraft: [NSManagedObjectID: Aircraft]
}

extension NSManagedObject {
  fileprivate func string(_ key: String) -> String? { value(forKey: key) as? String }

  fileprivate func related(_ key: String) -> NSManagedObject? {
    value(forKey: key) as? NSManagedObject
  }

  fileprivate func relatedSet(_ key: String) -> [NSManagedObject] {
    ((value(forKey: key) as? Set<NSManagedObject>) ?? []).map(\.self)
  }
}
