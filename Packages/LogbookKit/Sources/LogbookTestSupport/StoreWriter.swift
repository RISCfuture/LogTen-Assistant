import CoreData
import Foundation
import LogbookModel

/// Inserts a ``SyntheticLogbook``'s records into a context, the way LogTen lays them out.
struct StoreWriter {
  let context: NSManagedObjectContext

  func insert(_ logbook: SyntheticLogbook) throws {
    insertCustomFieldTitles(logbook.customFieldTitles)
    let people = Dictionary(uniqueKeysWithValues: logbook.people.map { ($0.id, insert($0)) })
    let places = Dictionary(uniqueKeysWithValues: logbook.places.map { ($0.id, insert($0)) })
    let types = Dictionary(uniqueKeysWithValues: logbook.aircraftTypes.map { ($0.id, insert($0)) })
    let aircraft = Dictionary(
      uniqueKeysWithValues: logbook.aircraft.map { ($0.id, insert($0, types: types)) }
    )
    let flights = Dictionary(
      uniqueKeysWithValues: logbook.flights.map { flight in
        (flight.id, insert(flight, people: people, places: places, aircraft: aircraft))
      }
    )
    for group in logbook.groups { insert(group, flights: flights) }
  }

  private func object(_ entityName: String, id: String? = nil) -> NSManagedObject {
    let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    if let id { object.setValue(id, forKey: "logTen_uniqueID") }
    return object
  }

  private func insertCustomFieldTitles(_ titles: [LogTenFieldKey: String]) {
    for (key, title) in titles {
      let property = object("LogTenCustomizationProperty")
      property.setValue(key.rawValue, forKey: "logTenProperty_key")
      property.setValue(title, forKey: "logTenCustomizationProperty_title")
      property.setValue(
        key.customSlot.map { "Custom \($0.number)" },
        forKey: "logTenCustomizationProperty_defaultTitle"
      )
    }
  }

  private func slotProperty<Value: LogTenSlotValue & Equatable>(_ value: Value?, title: String)
    -> NSManagedObject?
  {
    guard let value, let slot = Value.defaultSlots.first(where: { $0.value == value })?.key else {
      return nil
    }
    let property = object("LogTenCustomizationProperty")
    property.setValue("\(Value.slotPrefix)\(slot)", forKey: "logTenProperty_key")
    property.setValue(title, forKey: "logTenCustomizationProperty_title")
    return property
  }

  private func insert(_ person: SyntheticLogbook.Person) -> NSManagedObject {
    let object = object("Person", id: person.id)
    object.setValue(person.name, forKey: "person_name")
    object.setValue(person.isMe, forKey: "person_isMe")
    return object
  }

  private func insert(_ place: SyntheticLogbook.Place) -> NSManagedObject {
    let object = object("Place", id: place.id)
    object.setValue(place.identifier, forKey: "place_identifier")
    object.setValue(place.ICAO, forKey: "place_icaoid")
    return object
  }

  private func insert(_ type: SyntheticLogbook.AircraftType) -> NSManagedObject {
    let object = object("AircraftType", id: type.id)
    object.setValue(type.type, forKey: "aircraftType_type")
    object.setValue(
      slotProperty(type.category, title: type.category.rawValue),
      forKey: "aircraftType_category"
    )
    object.setValue(
      slotProperty(type.aircraftClass, title: type.aircraftClass?.rawValue ?? ""),
      forKey: "aircraftType_aircraftClass"
    )
    object.setValue(
      slotProperty(type.engineType, title: type.engineType?.rawValue ?? ""),
      forKey: "aircraftType_engineType"
    )
    for (slot, value) in type.customAttributes {
      object.setValue(value, forKey: LogTenFieldKey.custom(.aircraftTypeAttribute, slot).rawValue)
    }
    return object
  }

  private func insert(_ aircraft: SyntheticLogbook.Aircraft, types: [String: NSManagedObject])
    -> NSManagedObject
  {
    let object = object("Aircraft", id: aircraft.id)
    object.setValue(aircraft.registration, forKey: "aircraft_aircraftID")
    object.setValue(aircraft.isTailwheel, forKey: "aircraft_tailwheel")
    object.setValue(types[aircraft.typeID], forKey: "aircraft_aircraftType")
    return object
  }

  private func insert(
    _ flight: SyntheticLogbook.Flight,
    people: [String: NSManagedObject],
    places: [String: NSManagedObject],
    aircraft: [String: NSManagedObject]
  ) -> NSManagedObject {
    let object = object("Flight", id: flight.id)
    object.setValue(flight.date, forKey: LogTenFieldKey.flightDate.rawValue)
    for (key, value) in flight.values { object.setValue(value.objectValue, forKey: key.rawValue) }
    object.setValue(flight.aircraftID.flatMap { aircraft[$0] }, forKey: "flight_aircraft")
    object.setValue(flight.fromID.flatMap { places[$0] }, forKey: "flight_fromPlace")
    object.setValue(flight.toID.flatMap { places[$0] }, forKey: "flight_toPlace")

    if !flight.crew.isEmpty {
      let crew = self.object("FlightCrew")
      for (relationship, personID) in flight.crew {
        crew.setValue(people[personID], forKey: relationship)
      }
      object.setValue(crew, forKey: "flight_flightCrew")
    }
    if !flight.passengerIDs.isEmpty {
      let passengers = self.object("FlightPassengers")
      for (index, personID) in flight.passengerIDs.enumerated() {
        passengers.setValue(people[personID], forKey: "flightPassengers_pax\(index + 1)")
      }
      object.setValue(passengers, forKey: "flight_flightPassengers")
    }
    if !flight.approaches.isEmpty {
      let container = self.object("FlightApproaches")
      for (index, approach) in flight.approaches.enumerated() {
        container.setValue(
          insert(approach, places: places),
          forKey: "flightApproaches_approach\(index + 1)"
        )
      }
      object.setValue(container, forKey: "flight_flightApproaches")
    }
    if flight.isSigned { object.setValue(self.object("Signature"), forKey: "flight_signature") }
    return object
  }

  private func insert(_ approach: SyntheticLogbook.Approach, places: [String: NSManagedObject])
    -> NSManagedObject
  {
    let object = object("Approach", id: approach.id)
    object.setValue(approach.type, forKey: "approach_type")
    object.setValue(approach.runway, forKey: "approach_comment")
    object.setValue(approach.quantity, forKey: "approach_quantity")
    object.setValue(approach.placeID.flatMap { places[$0] }, forKey: "approach_place")
    return object
  }

  private func insert(_ group: SyntheticLogbook.Group, flights: [String: NSManagedObject]) {
    let object = object("Group", id: group.id)
    object.setValue(group.name, forKey: "group_name")
    object.setValue(group.predicateFormat, forKey: "group_predicateString")
    object.mutableSetValue(forKey: "group_flights").addObjects(
      from: group.flightIDs.compactMap { flights[$0] }
    )
  }
}

extension FieldValue {
  /// The value as Core Data stores it.
  var objectValue: Any? {
    switch self {
      case .null: nil
      case .integer(let value): value
      case .number(let value): value
      case .boolean(let value): value
      case .text(let value): value
      case .date(let value): value
    }
  }
}
