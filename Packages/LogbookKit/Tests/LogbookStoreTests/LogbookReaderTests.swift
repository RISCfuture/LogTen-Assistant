import CoreData
import Foundation
import LogbookModel
import LogbookStore
import LogbookTestSupport
import Synchronization
import Testing

@Suite(.requiresLogTen)
struct `Snapshotting and reading` {
  private let directory: TemporaryDirectory
  private let store: SyntheticStore

  init() throws {
    directory = try TemporaryDirectory()
    store = try SyntheticLogbook.sample.write(into: directory.url)
  }

  private func snapshot(_ name: String = "snapshot") async throws -> LogbookSnapshot {
    try await LogbookSnapshotter().snapshot(of: store.location, into: directory.path(name))
  }

  private func readSample() async throws -> Logbook {
    try await LogbookReader(snapshot: snapshot()).read()
  }

  private func read(_ logbook: SyntheticLogbook, as name: String) async throws -> Logbook {
    let store = try logbook.write(into: directory.path(name))
    let snapshot = try await LogbookSnapshotter().snapshot(
      of: store.location,
      into: directory.path("\(name)-snapshot")
    )
    return try await LogbookReader(snapshot: snapshot).read()
  }

  // MARK: Snapshots

  @Test
  func `copies an open store into a self-contained snapshot`() async throws {
    let walPath = store.location.storeURL.path(percentEncoded: false) + "-wal"
    #expect(FileManager.default.fileExists(atPath: walPath))

    let snapshot = try await snapshot()

    let files = try FileManager.default.contentsOfDirectory(
      atPath: snapshot.directory.path(percentEncoded: false)
    )
    #expect(files == [LogbookLocation.storeFileName])
    #expect(snapshot.sourceFiles.map(\.name).contains(LogbookLocation.storeFileName + "-wal"))
    #expect(FileManager.default.fileExists(atPath: walPath))
    #expect(try await LogbookReader(snapshot: snapshot).read().flights.count == 2)
  }

  @Test
  func `reports the copy and the read as fractions ending at one`() async throws {
    let copied = Mutex([Double]())
    let snapshot = try await LogbookSnapshotter().snapshot(
      of: store.location,
      into: directory.path("progress"),
      progress: { fraction in copied.withLock { $0.append(fraction) } }
    )
    let read = Mutex([Double]())
    _ = try await LogbookReader(snapshot: snapshot).read { fraction in
      read.withLock { $0.append(fraction) }
    }

    #expect(copied.withLock { $0.first == 0 && $0.last == 1 })
    #expect(read.withLock { $0.first == 0 && $0.last == 1 })
  }

  @Test
  func `refuses to overwrite an existing folder`() async throws {
    let existing = directory.path("existing")
    try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
    await #expect(throws: CocoaError.self) {
      try await LogbookSnapshotter().snapshot(of: store.location, into: existing)
    }
  }

  // MARK: Records

  @Test
  func `reads typed flight fields, people and places`() async throws {
    let logbook = try await readSample()
    let flight = try #require(logbook.flights.first)

    #expect(flight.id.rawValue == "F-night")
    #expect(flight.flightKey == "KEY-1")
    #expect(flight.times == FlightTimes(total: 90, PIC: 90, night: 30))
    #expect(flight.hobbsStart == 1233.4)
    #expect(flight.counts == FlightCounts(nightTakeoffs: 1, nightLandings: 2, fullStops: 2))
    #expect(flight.events.blockTime == Measurement(value: 90, unit: .minutes))
    #expect(flight.from?.preferredIdentifier == "KSQL")
    #expect(flight.crew.PIC?.name == "Pat Pilot")
    #expect(flight.passengers.map(\.name) == ["Quinn Passenger"])
    #expect(flight.approaches.map(\.type) == [.ILS])
    #expect(flight.approaches.first?.place?.identifier == "HAF")
    #expect(flight.approaches.first?.runway == "12")
    #expect(flight.approaches.first?.count == 3)
    #expect(!flight.isLocked && !flight.isSigned)
  }

  @Test
  func `reads aircraft types with their category slots`() async throws {
    let aircraft = try #require(try await readSample().aircraft.first)
    #expect(aircraft.registration == "N12345")
    #expect(aircraft.type?.category == .airplane)
    #expect(aircraft.type?.aircraftClass == .singleEngineLand)
    #expect(aircraft.type?.engineType == .reciprocating)
  }

  @Test
  func `reads locked and signed entries and attributes without typed properties`() async throws {
    let flight = try #require(try await readSample().flights.last)
    #expect(flight.flightKey == nil)
    #expect(flight.isLocked)
    #expect(flight.isSigned)
    #expect(flight[field: LogTenFieldKey(.flight, "touchAndGoes")] == .integer(3))
  }

  @Test
  func `reads custom fields through a mapping suggested from their titles`() async throws {
    let logbook = try await readSample()
    let mapping = FieldMapping.suggested(for: logbook.customFields)
    let flight = try #require(logbook.flights.first)
    let type = try #require(flight.aircraft?.type)

    #expect(flight.count(for: .nightFullStops, in: mapping) == 2)
    #expect(flight.isMarked(.proficiencyCheck, in: mapping) == true)
    #expect(flight.person(for: .safetyPilot, in: mapping)?.name == "Sam Safety")
    #expect(flight[field: .custom(.flightCrew, 1)] == .text("Sam Safety"))
    #expect(type.typeCode(in: mapping) == "S22T")
  }

  @Test
  func `lists custom-field titles and whether the user renamed them`() async throws {
    let definitions = try await LogbookReader(snapshot: snapshot()).customFieldDefinitions()
    let byKey = Dictionary(uniqueKeysWithValues: definitions.map { ($0.key, $0) })

    #expect(byKey[.custom(.flightLanding, 5)]?.title == "Night Full Stops")
    #expect(byKey[.custom(.flightLanding, 5)]?.isRenamed == true)
    #expect(byKey[.custom(.flightTime, 2)]?.isRenamed == false)
  }

  @Test
  func `orders flights by date then departure`() async throws {
    let logbook = SyntheticLogbook(
      flights: [
        .init(id: "F-next-day", date: SyntheticLogbook.departure + 86_400),
        .init(
          id: "F-late",
          date: SyntheticLogbook.departure,
          values: [.flightActualDepartureTime: .date(SyntheticLogbook.departure + 3_600)]
        ),
        .init(
          id: "F-early",
          date: SyntheticLogbook.departure,
          values: [.flightActualDepartureTime: .date(SyntheticLogbook.departure)]
        )
      ]
    )

    let flights = try await read(logbook, as: "ordered").flights

    #expect(flights.map(\.id.rawValue) == ["F-early", "F-late", "F-next-day"])
  }

  // MARK: Identity and fingerprints

  @Test
  func `identifies the logbook by its store UUID`() async throws {
    let first = try await LogbookReader(snapshot: snapshot("first"))
    let second = try await LogbookReader.identity(ofStoreAt: snapshot("second").storeURL)
    #expect(first.identity.storeUUID == second.storeUUID)
    #expect(!first.identity.modelVersionIdentifiers.isEmpty)
  }

  @Test
  func `changes a flight's fingerprint only when the flight changes`() async throws {
    let before = try await LogbookReader(snapshot: snapshot("before")).read().fingerprints
    try store.updateFlight("F-signed", [.flightNight: .integer(12)])
    let after = try await LogbookReader(snapshot: snapshot("after")).read().fingerprints

    let changed = RecordID(rawValue: "F-signed")
    let unchanged = RecordID(rawValue: "F-night")
    #expect(before[changed] != after[changed])
    #expect(before[unchanged] != nil)
    #expect(before[unchanged] == after[unchanged])
    #expect(before[RecordID(rawValue: "A-N12345")] == after[RecordID(rawValue: "A-N12345")])
  }

  // MARK: Groups

  @Test
  func `evaluates smart-group predicates against the snapshot`() async throws {
    let reader = try await LogbookReader(snapshot: snapshot())
    let groups = try await reader.read().groups
    let night = try #require(groups.first { $0.name == "Night" })
    let signed = try #require(groups.first { $0.name == "Signed" })

    #expect(night.isSmart)
    #expect(try await reader.flightIDs(in: night) == [RecordID(rawValue: "F-night")])
    #expect(try await reader.flightIDs(in: signed) == [RecordID(rawValue: "F-signed")])
  }

  @Test(arguments: ["flight_night >", "flight_noSuchField > 0"])
  func `reports predicates that don't parse or don't fit the model`(_ format: String) async throws {
    let reader = try await LogbookReader(snapshot: snapshot())
    await #expect {
      try await reader.flightIDs(matching: format)
    } throws: { error in
      guard case .invalidPredicate(let failed, _) = error as? LogbookStoreError else {
        return false
      }
      return failed == format
    }
  }

  // MARK: Validation

  @Test
  func `rejects a mapping that names a field the model lacks`() async throws {
    let reader = try await LogbookReader(snapshot: snapshot())
    var mapping = FieldMapping()
    try mapping.assign(LogTenFieldKey(.flight, "noSuchField"), to: .interceptingAndTracking)

    #expect(throws: LogbookStoreError.unknownField(LogTenFieldKey(.flight, "noSuchField"))) {
      try reader.validate(mapping)
    }
    #expect(throws: Never.self) { try reader.validate(FieldMapping()) }
  }
}

@Suite
struct `Unavailable stores` {
  @Test
  func `reports a missing data model`() {
    let missing = URL(filePath: "/nonexistent/CNLogBookDocument.momd", directoryHint: .isDirectory)
    #expect(throws: LogbookStoreError.modelUnavailable(missing)) {
      try LogTenModel(url: missing).load()
    }
  }

  @Test
  func `reports a file that isn't a store`() throws {
    let directory = try TemporaryDirectory()
    let storeURL = directory.path("Garbage.sql")
    try Data("not a database".utf8).write(to: storeURL)

    #expect {
      try LogbookReader.identity(ofStoreAt: storeURL)
    } throws: { error in
      guard case .unreadableStore(storeURL, _) = error as? LogbookStoreError else { return false }
      return true
    }
  }
}

@Suite(.requiresLogTen)
struct `Model compatibility` {
  private static func writeStore(at url: URL) throws {
    let entity = NSEntityDescription()
    entity.name = "Flight"
    let attribute = NSAttributeDescription()
    attribute.name = "flight_totalTime"
    attribute.type = .integer32
    entity.properties = [attribute]
    let model = NSManagedObjectModel()
    model.entities = [entity]

    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
    try coordinator.remove(store)
  }

  @Test
  func `rejects a store written with a different model`() throws {
    let directory = try TemporaryDirectory()
    let storeURL = directory.path("Other.sql")
    try Self.writeStore(at: storeURL)

    #expect {
      try LogbookReader(storeURL: storeURL)
    } throws: { error in
      guard case .modelMismatch = error as? LogbookStoreError else { return false }
      return true
    }
  }
}
