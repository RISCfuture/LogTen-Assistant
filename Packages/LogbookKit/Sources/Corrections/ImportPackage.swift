public import Foundation
public import LogbookModel

/**
 A LogTen `addEntities` import package: changes to existing flights, addressed by flight key.

 LogTen's documented import (`logten://v2/addEntities?package=…`) updates the flight whose
 `flight_key` matches each entity, and asks the user to confirm. The package is JSON with
 compact separators and ASCII-only escapes, members in a fixed order, percent-encoded into the
 URL, exactly as cleanup-logten wrote the packages it applied.
 */
public struct ImportPackage: Hashable, Codable, Sendable {
  private static let urlPrefix = "logten://v2/addEntities?package="

  /// Bytes that percent-encoding leaves alone: Python's `quote(…, safe="")` set.
  private static let unreservedBytes = Set(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~".utf8
  )

  /// Who wrote the package, and how LogTen should treat its times.
  public var metadata: ImportPackageMetadata

  /// The flights to change, in order.
  public var entities: [ImportEntity]

  /// The package as JSON text.
  public var json: String {
    var output = "{\"metadata\":"
    output += metadata.json
    output += ",\"entities\":["
    output += entities.map(\.json).joined(separator: ",")
    output += "]}"
    return output
  }

  /// The URL that hands the package to LogTen.
  public var url: URL {
    var encoded = Self.urlPrefix
    for byte in json.utf8 {
      if Self.unreservedBytes.contains(byte) {
        encoded.unicodeScalars.append(Unicode.Scalar(byte))
      } else {
        encoded += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2)
      }
    }
    guard let url = URL(string: encoded) else {
      preconditionFailure("A percent-encoded package always forms a valid URL")
    }
    return url
  }

  /// Creates a package.
  public init(metadata: ImportPackageMetadata, entities: [ImportEntity]) {
    self.metadata = metadata
    self.entities = entities
  }

  /**
   Creates the package that applies a batch: one entity per flight, with that flight's changed
   fields in the batch's order.

   - Throws: ``CorrectionError`` if a change has no flight key, names a field that isn't
     importable, or has a value that doesn't suit its field, or if a flight changes the same
     field twice.
   */
  public init(batch: CorrectionBatch, metadata: ImportPackageMetadata) throws(CorrectionError) {
    var order = [String]()
    var fields = [String: [ImportEntity.Field]]()
    for change in batch.changes {
      guard let key = change.flightKey else { throw .missingFlightKey(change.recordID) }
      guard let value = ImportField.packageValue(change.new, for: change.field) else {
        throw ImportField.isImportable(change.field)
          ? .unsuitableValue(change.field, change.new) : .fieldNotImportable(change.field)
      }
      if fields[key] == nil { order.append(key) }
      guard fields[key, default: []].allSatisfy({ $0.key != change.field }) else {
        throw .conflictingChanges(change.recordID, change.field)
      }
      fields[key, default: []].append(.init(key: change.field, value: value))
    }
    self.init(
      metadata: metadata,
      entities: order.map { ImportEntity(flightKey: $0, fields: fields[$0] ?? []) }
    )
  }
}

/// The metadata of an import package.
public struct ImportPackageMetadata: Hashable, Codable, Sendable {
  /// The application that wrote the package.
  public var application: String

  /// The writing application's version.
  public var version: String

  /// Whether times are UTC. Corrections always write UTC.
  public var timesAreZulu: Bool

  /// Whether LogTen should fill in derived times. Corrections never let it, so only the fields
  /// in the package change.
  public var shouldApplyAutoFillTimes: Bool

  var json: String {
    "{\"application\":\(CanonicalJSON.string(for: .string(application)))"
      + ",\"version\":\(CanonicalJSON.string(for: .string(version)))"
      + ",\"timesAreZulu\":\(timesAreZulu)"
      + ",\"shouldApplyAutoFillTimes\":\(shouldApplyAutoFillTimes)}"
  }

  /// Creates metadata for UTC times without auto-fill.
  public init(application: String = "LogTen Assistant", version: String) {
    self.application = application
    self.version = version
    timesAreZulu = true
    shouldApplyAutoFillTimes = false
  }
}

/// One flight in an import package.
public struct ImportEntity: Hashable, Codable, Sendable {
  /// The key of the flight to change.
  public var flightKey: String

  /// The fields to set, in order.
  public var fields: [Field]

  var json: String {
    var output = "{\"entity_name\":\"Flight\",\"flight_key\":"
    output += CanonicalJSON.string(for: .string(flightKey))
    for field in fields {
      output += ","
      output += CanonicalJSON.string(for: .string(field.key.rawValue))
      output += ":"
      output += CanonicalJSON.string(for: field.value)
    }
    return output + "}"
  }

  /// Creates an entity.
  public init(flightKey: String, fields: [Field]) {
    self.flightKey = flightKey
    self.fields = fields
  }

  /// One field of an entity and its package value.
  public struct Field: Hashable, Codable, Sendable {
    /// The field.
    public var key: LogTenFieldKey

    /// The value as the package writes it.
    public var value: JSONValue

    /// Creates a field.
    public init(key: LogTenFieldKey, value: JSONValue) {
      self.key = key
      self.value = value
    }
  }
}

extension String {
  fileprivate func leftPadded(to width: Int) -> String {
    String(repeating: "0", count: Swift.max(0, width - count)) + self
  }
}
