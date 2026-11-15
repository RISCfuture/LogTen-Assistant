public import Foundation
public import LogbookModel

/**
 Confirms that LogTen applied a batch, and nothing else, by comparing fresh snapshots with the
 snapshot taken before any batch was applied.

 LogTen asks the user to confirm each import and reports nothing back, so the verifier polls:
 it takes snapshots until the batch's new values appear or the timeout passes, then checks
 that

 - the same flights exist, so none was added or removed;
 - every batch flight is still unlocked and unsigned, and keeps its unique flight key;
 - every field of every flight holds its old value, except the fields of applied batches,
   which hold their new values;
 - crew, passengers and approaches are unchanged, and no signature appeared or disappeared.

 Clearing a minute or count field stores zero, so null and zero are the same value there.

 Side effects of LogTen's import are allowed when a change of the same flight explains them:

 - when an entry has no out or in time, LogTen moves its date's clock time to the new takeoff
   time on the same calendar day, and it recomputes the airborne duration from the takeoff and
   landing times;
 - the PIC and SIC capacity flags follow PIC and SIC time;
 - the special night flags follow the night times;
 - total instrument time is the sum of actual and simulated instrument time;
 - the numbered category, aircraft class and engine type totals follow total time.
 */
public struct BatchVerifier: Sendable {
  private static let durationField = LogTenFieldKey(.flight, "duration")
  private static let totalInstrumentField = LogTenFieldKey(.flight, "totalInstrument")
  private static let specialNightFlagsField = LogTenFieldKey(.flight, "specialNightFlags")
  private static let picCapacityField = LogTenFieldKey(.flight, "picCapacity")
  private static let sicCapacityField = LogTenFieldKey(.flight, "sicCapacity")
  private static let nightFields: Set<LogTenFieldKey> = [
    .flightNight, .flightPICNight, .flightSICNight, .flightP1USNight, .flightDualReceivedNight,
    .flightCrossCountryNight
  ]
  private static let instrumentFields: Set<LogTenFieldKey> = [
    .flightActualInstrument, .flightSimulatedInstrument
  ]
  private static let totalTimeTotalPrefixes = [
    "flight_category", "flight_aircraftClass", "flight_engineType"
  ]
  private static let durationToleranceMinutes = 1.0
  private static let secondsPerMinute = 60.0

  private static let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  /// How long to wait for LogTen to apply a batch.
  public var timeout: Duration

  /// How long to wait between snapshots.
  public var pollInterval: Duration

  /// Creates a verifier.
  public init(timeout: Duration = .seconds(40), pollInterval: Duration = .milliseconds(500)) {
    self.timeout = timeout
    self.pollInterval = pollInterval
  }

  /**
   Verifies a batch in one snapshot.

   - Parameters:
     - batch: The batch to verify.
     - applied: Batches applied and verified earlier, since `before` was taken.
     - before: The snapshot taken before the first batch was delivered.
     - current: A snapshot taken after `batch` was delivered.
   - Returns: Every discrepancy found, and every field that changed.
   */
  public static func verify(
    _ batch: CorrectionBatch,
    after applied: [CorrectionBatch] = [],
    before: Logbook,
    current: Logbook
  ) -> BatchVerification {
    let old = FlightIndex(before)
    let new = FlightIndex(current)
    var verification = BatchVerification(batchID: batch.id)
    verification.issues += identityIssues(old: old, new: new)
    verification.issues += batchFlightIssues(batch, new: new)

    let expected = expectedValues(of: applied + [batch], in: old)
    for (id, original) in old.flights.sorted(by: { $0.key < $1.key }) {
      guard let updated = new.flights[id] else { continue }
      compare(original, updated, expected: expected[id] ?? [:], into: &verification)
    }
    return verification
  }

  /// Whether every change of a batch shows in a snapshot.
  public static func isApplied(_ batch: CorrectionBatch, in logbook: Logbook) -> Bool {
    let flights = FlightIndex(logbook).flights
    return batch.changes.allSatisfy { change in
      guard let flight = flights[change.recordID] else { return false }
      return flight[field: change.field].zeroingEmpty(for: change.field)
        .matches(flight.normalized(change.new, for: change.field).zeroingEmpty(for: change.field))
    }
  }

  private static func identityIssues(old: FlightIndex, new: FlightIndex) -> [VerificationIssue] {
    let before = Set(old.flights.keys)
    let after = Set(new.flights.keys)
    var issues = [VerificationIssue]()
    if !after.subtracting(before).isEmpty {
      issues.append(.flightsAdded(after.subtracting(before).sorted()))
    }
    if !before.subtracting(after).isEmpty {
      issues.append(.flightsRemoved(before.subtracting(after).sorted()))
    }
    return issues
  }

  private static func batchFlightIssues(_ batch: CorrectionBatch, new: FlightIndex)
    -> [VerificationIssue]
  {
    var issues = [VerificationIssue]()
    var checked = Set<RecordID>()
    for change in batch.changes where checked.insert(change.recordID).inserted {
      guard let flight = new.flights[change.recordID] else { continue }
      if flight.isLocked || flight.isSigned { issues.append(.batchFlightProtected(flight.id)) }
      if flight.flightKey != change.flightKey { issues.append(.flightKeyChanged(flight.id)) }
      if let key = flight.flightKey, new.flightKeyCounts[key, default: 0] > 1 {
        issues.append(.flightKeyNotUnique(flight.id))
      }
    }
    return issues
  }

  private static func expectedValues(of batches: [CorrectionBatch], in old: FlightIndex)
    -> [RecordID: [LogTenFieldKey: FieldValue]]
  {
    var expected = [RecordID: [LogTenFieldKey: FieldValue]]()
    for change in batches.flatMap(\.changes) {
      guard let flight = old.flights[change.recordID] else { continue }
      expected[change.recordID, default: [:]][change.field] = flight.normalized(
        change.new,
        for: change.field
      )
    }
    return expected
  }

  private static func compare(
    _ original: Flight,
    _ updated: Flight,
    expected: [LogTenFieldKey: FieldValue],
    into verification: inout BatchVerification
  ) {
    let before = original.allFieldValues
    let after = updated.allFieldValues
    for field in Set(before.keys).union(after.keys).sorted() {
      let old = (before[field] ?? .null).zeroingEmpty(for: field)
      let new = (after[field] ?? .null).zeroingEmpty(for: field)
      let wanted = expected[field]?.zeroingEmpty(for: field) ?? old
      if !new.matches(wanted) {
        if isAllowedSideEffect(
          field,
          original: original,
          updated: updated,
          changed: Set(expected.keys)
        ) {
          verification.observedChanges.append(
            .init(recordID: original.id, field: field, old: old, new: new, isSideEffect: true)
          )
          continue
        }
        verification.issues.append(
          .unexpectedValue(original.id, field, expected: wanted, found: new)
        )
      }
      if !new.matches(old) {
        verification.observedChanges.append(
          .init(recordID: original.id, field: field, old: old, new: new, isSideEffect: false)
        )
      }
    }
    if original.crew != updated.crew || original.passengers != updated.passengers
      || original.approaches != updated.approaches
    {
      verification.issues.append(.crewOrApproachesChanged(original.id))
    }
    if original.isSigned != updated.isSigned {
      verification.issues.append(.signatureChanged(original.id))
    }
  }

  private static func isAllowedSideEffect(
    _ field: LogTenFieldKey,
    original: Flight,
    updated: Flight,
    changed: Set<LogTenFieldKey>
  ) -> Bool {
    guard !changed.isEmpty else { return false }
    switch field {
      case picCapacityField: return isCapacity(field, following: .flightPIC, in: updated, changed)
      case sicCapacityField: return isCapacity(field, following: .flightSIC, in: updated, changed)
      case specialNightFlagsField: return !changed.isDisjoint(with: nightFields)
      case totalInstrumentField:
        return !changed.isDisjoint(with: instrumentFields)
          && updated[field: field].number
            == Double(updated.times.actualInstrument + updated.times.simulatedInstrument)
      case .flightDate:
        return original.events.out == nil && original.events.in == nil
          && utcCalendar.isDate(original.date, inSameDayAs: updated.date)
          && updated.events.off.map { $0.timeIntervalSince(updated.date) == 0 } == true
      case durationField:
        guard let minutes = updated[field: field].number else { return false }
        guard let off = updated.events.off, let on = updated.events.on else { return minutes == 0 }
        return abs(minutes - on.timeIntervalSince(off) / secondsPerMinute)
          <= durationToleranceMinutes
      default:
        return isTotalTimeTotal(field, updated: updated, changed: changed)
    }
  }

  private static func isCapacity(
    _ field: LogTenFieldKey,
    following role: LogTenFieldKey,
    in updated: Flight,
    _ changed: Set<LogTenFieldKey>
  ) -> Bool {
    changed.contains(role)
      && updated[field: field] == .boolean((updated[field: role].number ?? 0) > 0)
  }

  private static func isTotalTimeTotal(
    _ field: LogTenFieldKey,
    updated: Flight,
    changed: Set<LogTenFieldKey>
  ) -> Bool {
    changed.contains(.flightTotalTime)
      && totalTimeTotalPrefixes.contains { field.rawValue.hasPrefix($0) }
      && updated[field: field].number == Double(updated.times.total)
  }

  /**
   Waits for a batch to appear in the logbook, then verifies it.

   - Parameters:
     - batch: The batch just delivered.
     - applied: Batches applied and verified earlier, since `before` was taken.
     - before: The snapshot taken before the first batch was delivered.
     - snapshot: Takes and reads a fresh snapshot of the logbook.
   - Returns: The verification of the last snapshot taken.
   */
  public func waitAndVerify(
    _ batch: CorrectionBatch,
    after applied: [CorrectionBatch] = [],
    before: Logbook,
    snapshot: () async throws -> Logbook
  ) async throws -> BatchVerification {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    var current = try await snapshot()
    while !Self.isApplied(batch, in: current), clock.now < deadline {
      try await Task.sleep(for: pollInterval)
      current = try await snapshot()
    }
    return Self.verify(batch, after: applied, before: before, current: current)
  }
}

/// The outcome of verifying one batch.
public struct BatchVerification: Hashable, Codable, Sendable {
  /// The batch verified.
  public var batchID: String

  /// When it was verified.
  public var verifiedAt: Date

  /// Every discrepancy found; empty if the batch applied exactly as planned.
  public var issues: [VerificationIssue]

  /// Every field that differs from the snapshot before the first batch.
  public var observedChanges: [ObservedChange]

  /// Whether the batch applied exactly as planned.
  public var isVerified: Bool { issues.isEmpty }

  /// Creates a verification with no findings yet.
  public init(batchID: String, verifiedAt: Date = .now) {
    self.batchID = batchID
    self.verifiedAt = verifiedAt
    issues = []
    observedChanges = []
  }
}

/// A field that changed between snapshots.
public struct ObservedChange: Hashable, Codable, Sendable {
  /// The flight.
  public var recordID: RecordID
  /// The field.
  public var field: LogTenFieldKey
  /// The value before the first batch.
  public var old: FieldValue
  /// The value now.
  public var new: FieldValue
  /// Whether LogTen changed the field as a side effect of an applied field.
  public var isSideEffect: Bool

  /// Creates an observed change.
  public init(
    recordID: RecordID,
    field: LogTenFieldKey,
    old: FieldValue,
    new: FieldValue,
    isSideEffect: Bool
  ) {
    self.recordID = recordID
    self.field = field
    self.old = old
    self.new = new
    self.isSideEffect = isSideEffect
  }
}

/// A discrepancy between a snapshot and the batches applied.
public enum VerificationIssue: Hashable, Codable, Sendable {
  /// Flights appeared that weren't in the snapshot before.
  case flightsAdded([RecordID])
  /// Flights disappeared.
  case flightsRemoved([RecordID])
  /// A batch flight is now locked or signed.
  case batchFlightProtected(RecordID)
  /// A batch flight's key changed.
  case flightKeyChanged(RecordID)
  /// A batch flight's key is no longer unique.
  case flightKeyNotUnique(RecordID)
  /// A field doesn't hold the value it should.
  case unexpectedValue(RecordID, LogTenFieldKey, expected: FieldValue, found: FieldValue)
  /// A flight's crew, passengers or approaches changed.
  case crewOrApproachesChanged(RecordID)
  /// A flight was signed or lost its signature.
  case signatureChanged(RecordID)
}

extension FieldValue {
  /// Zero in place of null for a minute or count field, which LogTen stores as zero when an
  /// import clears it.
  fileprivate func zeroingEmpty(for field: LogTenFieldKey) -> Self {
    isNull && ImportField.clearsToZero(field) ? .integer(0) : self
  }
}

extension Flight {
  /// The typed fields, which ``customValues`` and ``otherValues`` don't hold.
  private static let typedFields: [LogTenFieldKey] = [
    .flightKey, .flightIsLocked, .flightDate, .flightRoute, .flightDistance, .flightNumber,
    .flightRemarks, .flightActualDepartureTime, .flightTakeoffTime, .flightLandingTime,
    .flightActualArrivalTime, .flightOnDutyTime, .flightOffDutyTime, .flightHobbsStart,
    .flightHobbsStop, .flightTachStart, .flightTachStop, .flightTotalTime, .flightPIC, .flightSIC,
    .flightSolo, .flightNight, .flightCrossCountry, .flightDualGiven, .flightDualReceived,
    .flightActualInstrument, .flightSimulatedInstrument, .flightSimulator, .flightGround,
    .flightNightVisionGoggle, .flightDayTakeoffs, .flightNightTakeoffs, .flightDayLandings,
    .flightNightLandings, .flightFullStops, .flightNightVisionGoggleTakeoffs,
    .flightNightVisionGoggleLandings, .flightHolds, .flightReview,
    .flightInstrumentProficiencyCheck
  ]

  /// Every `flight_*` attribute the flight holds, by key.
  var allFieldValues: [LogTenFieldKey: FieldValue] {
    otherValues.merging(customValues) { $1 }
      .merging(Self.typedFields.map { ($0, self[field: $0]) }) { $1 }
      .filter { !$0.value.isNull }
  }
}
