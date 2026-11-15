public import Foundation
public import LogbookModel

/**
 Approved changes that can't go through LogTen's import, such as those on signed or locked
 flights, as instructions for making them by hand, with values the user can copy into LogTen.
 */
public struct ManualChecklist: Hashable, Codable, Sendable {
  /// The items, one per excluded change, in proposal order.
  public var items: [ManualChecklistItem]

  /// Creates a checklist.
  public init(items: [ManualChecklistItem]) {
    self.items = items
  }

  /// Creates the checklist for excluded operations.
  public init(excluded: [ExcludedOperation], logbook: Logbook) {
    let flights = FlightIndex(logbook).flights
    items = excluded.flatMap { excluded in
      excluded.operation.changes.map { change in
        ManualChecklistItem(
          change: change,
          finding: excluded.operation,
          flight: flights[change.recordID],
          fieldTitle: logbook.customField(for: change.field)?.title,
          issues: excluded.issues
        )
      }
    }
  }
}

/// One change to make by hand in LogTen.
public struct ManualChecklistItem: Identifiable, Hashable, Codable, Sendable {
  /// The item's identifier: its operation's, its record's and its field's.
  public var id: String { "\(operationID)/\(change.recordID.rawValue)/\(change.field.rawValue)" }

  /// The operation the change belongs to.
  public var operationID: String

  /// The finding the change resolves.
  public var findingID: FindingID

  /// The change.
  public var change: FieldChange

  /// The entry's date, if the entry still exists.
  public var flightDate: Date?

  /// The entry's aircraft registration.
  public var registration: String?

  /// The entry's departure and destination identifiers.
  public var route: String?

  /// The field's title as LogTen shows it.
  public var fieldTitle: String

  /// The value to replace, as LogTen displays it.
  public var oldValue: String

  /// The value to enter, as LogTen displays it.
  public var newValue: String

  /// Why the change couldn't be imported.
  public var issues: [PreflightIssue]

  /// What the user should do.
  public var instruction: String

  init(
    change: FieldChange,
    finding: CorrectionOperation,
    flight: Flight?,
    fieldTitle: String?,
    issues: [PreflightIssue]
  ) {
    operationID = finding.id
    findingID = finding.findingID
    self.change = change
    flightDate = flight?.date
    registration = flight?.aircraft?.registration
    route = flight.flatMap { flight in
      let places = [flight.from, flight.to].compactMap(\.?.preferredIdentifier)
      return places.isEmpty ? nil : places.joined(separator: "–")
    }
    self.fieldTitle = fieldTitle ?? String(change.field.attributeName)
    oldValue = DisplayValue.string(for: change.old, field: change.field)
    newValue = DisplayValue.string(for: change.new, field: change.field)
    self.issues = issues
    instruction = Self.instruction(for: issues)
  }

  private static func instruction(for issues: [PreflightIssue]) -> String {
    guard issues.allSatisfy(\.allowsManualEdit) else {
      return String(
        localized:
          "The entry no longer matches the audit. Run the audit again before changing it.",
        bundle: .module
      )
    }
    if issues.contains(where: { if case .signed = $0 { true } else { false } }) {
      return String(
        localized:
          "This entry is signed. Unlocking it in LogTen removes its signature. Make the change shown, then have the entry signed again; LogTen signs entries on iPhone or iPad.",
        bundle: .module
      )
    }
    if issues.contains(where: { if case .locked = $0 { true } else { false } }) {
      return String(
        localized:
          "This entry is locked. Unlock it in LogTen, make the change shown, then lock it again if you want it locked.",
        bundle: .module
      )
    }
    return String(
      localized:
        "Open the entry in LogTen to make the change shown, or use Flight Audit in LogTen on iPhone or iPad.",
      bundle: .module
    )
  }
}

/// Field values as LogTen displays them, for copying into LogTen by hand.
enum DisplayValue {
  private static let secondsPerMinute = 60

  static func string(for value: FieldValue, field: LogTenFieldKey) -> String {
    switch value {
      case .null:
        return String(localized: "None", bundle: .module)
      case .integer(let minutes) where field.isDuration:
        return Duration.seconds(minutes * secondsPerMinute).formatted(.time(pattern: .hourMinute))
      case .integer(let number):
        return number.formatted(.number.grouping(.never))
      case .number(let number):
        return number.formatted(.number.grouping(.never))
      case .boolean(let flag):
        return flag
          ? String(localized: "Yes", bundle: .module) : String(localized: "No", bundle: .module)
      case .text(let text):
        return text
      case .date(let date):
        return date.formatted(
          Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().time(
            includingFractionalSeconds: false
          )
        )
    }
  }
}

extension LogTenFieldKey {
  /// Whether the field holds minutes.
  fileprivate var isDuration: Bool {
    customSlot?.kind == .flightTime
      || [
        Self.flightTotalTime, .flightPIC, .flightSIC, .flightSolo, .flightNight,
        .flightCrossCountry, .flightDualGiven, .flightDualReceived, .flightActualInstrument,
        .flightSimulatedInstrument, .flightSimulator, .flightGround, .flightNightVisionGoggle,
        .flightPICNight, .flightSICNight, .flightDualReceivedNight, .flightP1US, .flightP1USNight,
        .flightCrossCountryNight
      ]
      .contains(self)
  }
}
