import Foundation
public import LogbookModel

/// A set of field changes applied to the logbook together.
public struct CorrectionBatch: Identifiable, Hashable, Codable, Sendable {
  private static let identifierLength = 20

  /// The batch's content-addressed identifier: the first 20 hexadecimal digits of the
  /// SHA-256 digest of its changes' canonical JSON.
  public let id: String

  /// The changes, grouped by flight in the order the flights first appear.
  public let changes: [FieldChange]

  /// The flight keys the batch changes, in order.
  public var flightKeys: [String] {
    var seen = Set<String>()
    return changes.compactMap(\.flightKey).filter { seen.insert($0).inserted }
  }

  /// The flights the batch changes.
  public var recordIDs: Set<RecordID> { Set(changes.map(\.recordID)) }

  /// The batch that undoes this one: the same fields, set back to their old values.
  public var compensating: Self {
    Self(
      changes: changes.map {
        FieldChange(
          flightKey: $0.flightKey,
          recordID: $0.recordID,
          field: $0.field,
          old: $0.new,
          new: $0.old
        )
      }
    )
  }

  /// Creates a batch and derives its identifier.
  public init(changes: [FieldChange]) {
    self.changes = changes
    id = String(
      CanonicalJSON.sha256(of: .array(changes.map(\.canonicalJSON))).prefix(Self.identifierLength)
    )
  }

  /**
   Splits changes into batches for applying: a pilot batch of one flight, so a problem shows up
   before it can affect many entries, then batches of at most `maximumFlights` flights.

   Changes to the same flight always stay in the same batch. Changes without a flight key
   can't be applied through LogTen and are left out.

   - Parameters:
     - changes: The approved changes.
     - maximumFlights: The most flights in any batch after the first.
   - Returns: The batches, pilot first.
   */
  public static func plan(_ changes: [FieldChange], maximumFlights: Int) -> [Self] {
    precondition(maximumFlights > 0, "Batches must hold at least one flight")
    let flights = changesByFlight(changes)
    guard let pilot = flights.first else { return [] }
    let rest = flights.dropFirst()
    let groups =
      [[pilot]]
      + stride(from: rest.startIndex, to: rest.endIndex, by: maximumFlights).map { start in
        Array(rest[start..<min(start + maximumFlights, rest.endIndex)])
      }
    return groups.map { Self(changes: $0.flatMap(\.self)) }
  }

  /**
   Splits changes into batches whose import URLs stay within a length LogTen and the system
   accept: a one-flight pilot batch, then as many flights per batch as fit.

   A flight whose changes alone exceed the limit gets a batch of its own. Changes without a
   flight key are left out.

   - Parameters:
     - changes: The approved changes.
     - maximumURLLength: The longest import URL, in characters.
     - metadata: The metadata the packages will carry.
   - Returns: The batches, pilot first.
   - Throws: ``CorrectionError`` if a change can't be packaged.
   */
  public static func plan(
    _ changes: [FieldChange],
    maximumURLLength: Int,
    metadata: ImportPackageMetadata
  ) throws(CorrectionError) -> [Self] {
    let flights = changesByFlight(changes)
    guard let pilot = flights.first else { return [] }
    let pilotBatch = Self(changes: pilot)
    _ = try ImportPackage(batch: pilotBatch, metadata: metadata)
    var batches = [pilotBatch]
    var current = [FieldChange]()
    for flight in flights.dropFirst() {
      let candidate = Self(changes: current + flight)
      let length = try ImportPackage(batch: candidate, metadata: metadata).url.absoluteString.count
      if length <= maximumURLLength || current.isEmpty {
        current = candidate.changes
      } else {
        batches.append(Self(changes: current))
        current = flight
      }
    }
    if !current.isEmpty { batches.append(Self(changes: current)) }
    return batches
  }

  private static func changesByFlight(_ changes: [FieldChange]) -> [[FieldChange]] {
    var order = [String]()
    var byFlight = [String: [FieldChange]]()
    for change in changes {
      guard let key = change.flightKey else { continue }
      if byFlight[key] == nil { order.append(key) }
      byFlight[key, default: []].append(change)
    }
    return order.map { byFlight[$0] ?? [] }
  }
}
