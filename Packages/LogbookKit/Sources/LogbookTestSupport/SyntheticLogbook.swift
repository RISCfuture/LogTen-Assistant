import CoreData
public import Foundation
public import LogbookModel
public import LogbookStore

/**
 A description of an invented logbook that can be written as a real LogTen store.

 Tests describe the records they need, then ``write(into:model:)`` creates a new Core Data store
 with LogTen's installed model in a `LogTenProData_<id>` folder. Nothing is copied from a real
 logbook. Records refer to each other by their LogTen unique IDs.
 */
public struct SyntheticLogbook: Sendable {
  /// Custom-field titles, by slot key. LogTen's default title is recorded alongside each.
  public var customFieldTitles: [LogTenFieldKey: String]

  /// People.
  public var people: [Person]

  /// Places.
  public var places: [Place]

  /// Aircraft types.
  public var aircraftTypes: [AircraftType]

  /// Aircraft.
  public var aircraft: [Aircraft]

  /// Flights.
  public var flights: [Flight]

  /// Groups.
  public var groups: [Group]

  /// Creates a synthetic logbook.
  public init(
    customFieldTitles: [LogTenFieldKey: String] = [:],
    people: [Person] = [],
    places: [Place] = [],
    aircraftTypes: [AircraftType] = [],
    aircraft: [Aircraft] = [],
    flights: [Flight] = [],
    groups: [Group] = []
  ) {
    self.customFieldTitles = customFieldTitles
    self.people = people
    self.places = places
    self.aircraftTypes = aircraftTypes
    self.aircraft = aircraft
    self.flights = flights
    self.groups = groups
  }

  /**
   Writes the logbook as a new LogTen store.

   - Parameters:
     - parent: The folder to create the `LogTenProData_<id>` folder in, standing in for LogTen's
       group container.
     - model: LogTen's installed data model.
   - Returns: The open store. It stays open, with recent writes in its write-ahead log as
     LogTen's would be, until it is closed or released.
   */
  public func write(into parent: URL, model: LogTenModel = .init()) throws -> SyntheticStore {
    let location = LogbookLocation(
      directory: parent.appending(
        path: LogbookLocation.dataFolderPrefix + UUID().uuidString,
        directoryHint: .isDirectory
      )
    )
    try FileManager.default.createDirectory(
      at: location.directory,
      withIntermediateDirectories: true
    )
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try model.load())
    _ = try coordinator.addPersistentStore(type: .sqlite, at: location.storeURL)

    let context = NSManagedObjectContext(.privateQueue)
    context.persistentStoreCoordinator = coordinator
    try context.performAndWait {
      try StoreWriter(context: context).insert(self)
      try context.save()
    }
    return SyntheticStore(location: location, coordinator: coordinator, context: context)
  }
}

extension SyntheticLogbook {
  /// A person.
  public struct Person: Sendable {
    /// The person's LogTen unique ID.
    public var id: String
    /// The person's name.
    public var name: String
    /// Whether LogTen marks the person as the logbook owner.
    public var isMe: Bool

    /// Creates a person.
    public init(id: String, name: String, isMe: Bool = false) {
      self.id = id
      self.name = name
      self.isMe = isMe
    }
  }

  /// A place.
  public struct Place: Sendable {
    /// The place's LogTen unique ID.
    public var id: String
    /// LogTen's identifier for the place.
    public var identifier: String
    /// The ICAO identifier.
    public var ICAO: String?

    /// Creates a place.
    public init(id: String, identifier: String, ICAO: String? = nil) {
      self.id = id
      self.identifier = identifier
      self.ICAO = ICAO
    }
  }

  /// An aircraft type. Its category, class and engine are stored as LogTen's default slots.
  public struct AircraftType: Sendable {
    /// The type's LogTen unique ID.
    public var id: String
    /// LogTen's type identifier.
    public var type: String
    /// The category.
    public var category: AircraftCategory
    /// The class.
    public var aircraftClass: AircraftClass?
    /// The engine type.
    public var engineType: EngineType?
    /// Custom attribute values, by slot number.
    public var customAttributes: [UInt: String]

    /// Creates an aircraft type.
    public init(
      id: String,
      type: String,
      category: AircraftCategory = .airplane,
      aircraftClass: AircraftClass? = .singleEngineLand,
      engineType: EngineType? = .reciprocating,
      customAttributes: [UInt: String] = [:]
    ) {
      self.id = id
      self.type = type
      self.category = category
      self.aircraftClass = aircraftClass
      self.engineType = engineType
      self.customAttributes = customAttributes
    }
  }

  /// An aircraft.
  public struct Aircraft: Sendable {
    /// The aircraft's LogTen unique ID.
    public var id: String
    /// The registration.
    public var registration: String
    /// The unique ID of the aircraft's type.
    public var typeID: String
    /// Whether the aircraft has tailwheel gear.
    public var isTailwheel: Bool

    /// Creates an aircraft.
    public init(id: String, registration: String, typeID: String, isTailwheel: Bool = false) {
      self.id = id
      self.registration = registration
      self.typeID = typeID
      self.isTailwheel = isTailwheel
    }
  }

  /// A flight.
  public struct Flight: Sendable {
    /// The flight's LogTen unique ID.
    public var id: String
    /// The date of the flight.
    public var date: Date
    /// The unique ID of the aircraft flown.
    public var aircraftID: String?
    /// The unique ID of the departure place.
    public var fromID: String?
    /// The unique ID of the destination place.
    public var toID: String?
    /// Other `flight_*` attribute values.
    public var values: [LogTenFieldKey: FieldValue]
    /// Crew, as `FlightCrew` relationship names (such as `flightCrew_PIC`) and person IDs.
    public var crew: [String: String]
    /// The unique IDs of the passengers, in seat order.
    public var passengerIDs: [String]
    /// Approaches.
    public var approaches: [Approach]
    /// Whether the flight carries a signature.
    public var isSigned: Bool

    /// Creates a flight.
    public init(
      id: String,
      date: Date,
      aircraftID: String? = nil,
      fromID: String? = nil,
      toID: String? = nil,
      values: [LogTenFieldKey: FieldValue] = [:],
      crew: [String: String] = [:],
      passengerIDs: [String] = [],
      approaches: [Approach] = [],
      isSigned: Bool = false
    ) {
      self.id = id
      self.date = date
      self.aircraftID = aircraftID
      self.fromID = fromID
      self.toID = toID
      self.values = values
      self.crew = crew
      self.passengerIDs = passengerIDs
      self.approaches = approaches
      self.isSigned = isSigned
    }
  }

  /// An approach on a flight.
  public struct Approach: Sendable {
    /// The approach's LogTen unique ID.
    public var id: String
    /// The approach type, as LogTen spells it.
    public var type: String
    /// The unique ID of the airport.
    public var placeID: String?
    /// The runway.
    public var runway: String?
    /// How many times the approach was flown.
    public var quantity: Int

    /// Creates an approach.
    public init(
      id: String,
      type: String,
      placeID: String? = nil,
      runway: String? = nil,
      quantity: Int = 1
    ) {
      self.id = id
      self.type = type
      self.placeID = placeID
      self.runway = runway
      self.quantity = quantity
    }
  }

  /// A group.
  public struct Group: Sendable {
    /// The group's LogTen unique ID.
    public var id: String
    /// The group's name.
    public var name: String
    /// The smart-group predicate.
    public var predicateFormat: String?
    /// Flights placed in the group.
    public var flightIDs: [String]

    /// Creates a group.
    public init(id: String, name: String, predicateFormat: String? = nil, flightIDs: [String] = [])
    {
      self.id = id
      self.name = name
      self.predicateFormat = predicateFormat
      self.flightIDs = flightIDs
    }
  }
}

/// A synthetic LogTen store, held open the way LogTen holds its own.
public final class SyntheticStore {
  /// Where the store is.
  public let location: LogbookLocation

  private var coordinator: NSPersistentStoreCoordinator?
  private let context: NSManagedObjectContext

  init(
    location: LogbookLocation,
    coordinator: NSPersistentStoreCoordinator,
    context: NSManagedObjectContext
  ) {
    self.location = location
    self.coordinator = coordinator
    self.context = context
  }

  /**
   Changes attributes of a flight, as editing it in LogTen would.

   - Parameters:
     - flightID: The flight's LogTen unique ID.
     - values: The new values; ``FieldValue/null`` clears an attribute.
   */
  public func updateFlight(_ flightID: String, _ values: [LogTenFieldKey: FieldValue]) throws {
    let context = context
    try context.performAndWait {
      let request = NSFetchRequest<NSManagedObject>(entityName: "Flight")
      request.predicate = NSPredicate(format: "logTen_uniqueID == %@", flightID)
      guard let flight = try context.fetch(request).first else {
        throw CocoaError(.coreData, userInfo: [NSDebugDescriptionErrorKey: "No flight \(flightID)"])
      }
      for (key, value) in values { flight.setValue(value.objectValue, forKey: key.rawValue) }
      try context.save()
    }
  }

  /// Closes the store, which checkpoints its write-ahead log.
  public func close() throws {
    guard let coordinator else { return }
    for store in coordinator.persistentStores { try coordinator.remove(store) }
    self.coordinator = nil
  }
}
