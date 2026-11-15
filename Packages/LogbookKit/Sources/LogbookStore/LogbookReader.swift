import CoreData
public import Foundation
public import LogbookModel

/**
 Reads a LogTen logbook snapshot into `LogbookModel` values.

 The reader opens the store read-only with LogTen's installed data model and never migrates
 it: a store written by a LogTen whose model differs is rejected with
 ``LogbookStoreError/modelMismatch(storeVersions:installedVersions:)``. Records are read with
 key-value coding, so every attribute the installed model defines, including all custom
 slots, reaches the model values without hard-coded field titles.

 Open only snapshots made by ``LogbookSnapshotter``, never LogTen's live store.
 */
public actor LogbookReader {
  private static var readOnlyOptions: [String: NSObject] {
    [
      NSReadOnlyPersistentStoreOption: true as NSNumber,
      NSMigratePersistentStoresAutomaticallyOption: false as NSNumber,
      NSInferMappingModelAutomaticallyOption: false as NSNumber,
      NSSQLitePragmasOption: ["journal_mode": "DELETE"] as NSObject
    ]
  }

  /// Which logbook the store belongs to.
  nonisolated public let identity: LogbookIdentity

  /// Every attribute key the installed model defines for the entities `LogTenFieldKey` can
  /// address.
  nonisolated public let availableFields: Set<LogTenFieldKey>

  private let context: NSManagedObjectContext

  /**
   Opens a snapshot.

   - Parameters:
     - snapshot: A snapshot made by ``LogbookSnapshotter``.
     - model: LogTen's installed data model.
   - Throws: ``LogbookStoreError`` if the model is missing or doesn't match, or the store
     can't be opened.
   */
  public init(snapshot: LogbookSnapshot, model: LogTenModel = .init()) throws {
    try self.init(storeURL: snapshot.storeURL, model: model)
  }

  /**
   Opens a store file read-only.

   - Parameters:
     - storeURL: A `LogTenCoreDataStore.sql` copy.
     - model: LogTen's installed data model.
   - Throws: ``LogbookStoreError`` if the model is missing or doesn't match, or the store
     can't be opened.
   */
  public init(storeURL: URL, model: LogTenModel = .init()) throws {
    let managedModel = try model.load()
    let metadata = try Self.metadata(ofStoreAt: storeURL)
    guard managedModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else {
      throw LogbookStoreError.modelMismatch(
        storeVersions: Self.versionIdentifiers(in: metadata),
        installedVersions: managedModel.versionIdentifiers.compactMap { $0 as? String }.sorted()
      )
    }

    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: managedModel)
    do {
      _ = try coordinator.addPersistentStore(
        type: .sqlite,
        at: storeURL,
        options: Self.readOnlyOptions
      )
    } catch {
      throw LogbookStoreError.unreadableStore(storeURL, reason: error.localizedDescription)
    }

    context = NSManagedObjectContext(.privateQueue)
    context.persistentStoreCoordinator = coordinator
    context.undoManager = nil
    identity = try Self.identity(from: metadata, storeURL: storeURL)
    availableFields = Self.fieldKeys(in: managedModel)
  }

  /**
   Reads a store's identity from its metadata without opening it.

   - Parameter storeURL: A `LogTenCoreDataStore.sql` file or copy.
   - Returns: The store's UUID and model versions.
   */
  public static func identity(ofStoreAt storeURL: URL) throws -> LogbookIdentity {
    try identity(from: metadata(ofStoreAt: storeURL), storeURL: storeURL)
  }

  private static func metadata(ofStoreAt storeURL: URL) throws -> [String: Any] {
    do {
      return try NSPersistentStoreCoordinator.metadataForPersistentStore(
        type: .sqlite,
        at: storeURL
      )
    } catch {
      throw LogbookStoreError.unreadableStore(storeURL, reason: error.localizedDescription)
    }
  }

  private static func identity(from metadata: [String: Any], storeURL: URL) throws
    -> LogbookIdentity
  {
    guard let uuidString = metadata[NSStoreUUIDKey] as? String,
      let uuid = UUID(uuidString: uuidString)
    else {
      throw LogbookStoreError.unreadableStore(storeURL, reason: "The store has no UUID.")
    }
    return LogbookIdentity(
      storeUUID: uuid,
      modelVersionIdentifiers: versionIdentifiers(in: metadata)
    )
  }

  private static func versionIdentifiers(in metadata: [String: Any]) -> [String] {
    ((metadata[NSStoreModelVersionIdentifiersKey] as? [Any]) ?? []).compactMap { $0 as? String }
      .sorted()
  }

  private static func fieldKeys(in model: NSManagedObjectModel) -> Set<LogTenFieldKey> {
    Set(
      LogTenEntity.allCases.flatMap { entity in
        (model.entitiesByName[entity.entityName]?.attributesByName.keys).map(Array.init) ?? []
      }
      .compactMap(LogTenFieldKey.init(rawValue:))
    )
  }

  /// Reads every record in the logbook.
  ///
  /// - Parameter progress: Called with the fraction of the flights converted, from `0` to `1`,
  ///   at most once per percent, once the flights have been fetched.
  public func read(progress: ProgressTally.Report? = nil) async throws -> Logbook {
    let identity = identity
    return try await perform { context in
      try LogbookMapper(context: context).logbook(identity: identity, progress: progress)
    }
  }

  /// Reads the custom fields and the titles the user gave them.
  public func customFieldDefinitions() async throws -> [CustomFieldDefinition] {
    try await perform { context in try LogbookMapper(context: context).customFieldDefinitions() }
  }

  /**
   Checks that every field a mapping names exists in the installed model.

   - Throws: ``LogbookStoreError/unknownField(_:)`` for the first field that doesn't.
   */
  nonisolated public func validate(_ mapping: FieldMapping) throws {
    for role in FieldRole.allCases {
      if let key = mapping[role], !availableFields.contains(key) {
        throw LogbookStoreError.unknownField(key)
      }
    }
  }

  /**
   Evaluates an `NSPredicate` format string against the logbook's flights, as LogTen does for
   a smart group.

   - Parameter predicateFormat: A predicate over `Flight` attributes and relationships.
   - Returns: The identifiers of the matching flights, sorted.
   - Throws: ``LogbookStoreError/invalidPredicate(_:reason:)`` if the format doesn't parse or
     names a key the model doesn't have.
   */
  public func flightIDs(matching predicateFormat: String) async throws -> [RecordID] {
    try await perform { context in
      try LogbookMapper(context: context).flightIDs(matching: predicateFormat)
    }
  }

  /**
   The flights in a group: those its predicate matches, or its assigned members if it has no
   predicate.

   - Parameter group: A group from `Logbook.groups`.
   - Returns: The identifiers of the group's flights, sorted.
   */
  public func flightIDs(in group: LogbookGroup) async throws -> [RecordID] {
    guard let format = group.predicateFormat else { return group.memberFlightIDs.sorted() }
    return try await flightIDs(matching: format)
  }

  private func perform<Result: Sendable>(
    _ body: @escaping @Sendable (NSManagedObjectContext) throws -> Result
  ) async throws -> Result {
    let context = context
    return try await context.perform { try body(context) }
  }
}

extension Error {
  /// The reason an Objective-C exception converted by `ObjCExceptionCatcher` gave.
  var objCExceptionReason: String {
    let error = self as NSError
    return (error.userInfo[NSDebugDescriptionErrorKey] as? String) ?? error.localizedDescription
  }
}
