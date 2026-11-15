import Foundation
import LogbookModel

/**
 A flight's recorded values grouped the way LogTen's inspector groups them, with the logbook's
 own titles for custom fields.

 Given a correction's changes, each item also carries the value the correction would write, so
 the inspector can show the change in place. Given the sources' discrepancies with the logbook,
 the item that shows each one carries it. Values that are unset before and after are left out.
 */
nonisolated struct FlightDetails {
  /// The sections that have at least one value, in LogTen's order.
  let sections: [Section]

  /**
   Collects a flight's details.

   - Parameters:
     - flight: The flight.
     - customFields: The logbook's custom-field definitions, for their titles.
     - timeZone: The pilot's time zone, for the flight date and for local times at places with
       no recorded time zone.
     - changes: A correction's changes; those to other records or entities are ignored. A detail
       a change touches is always shown, with the values explicit.
     - discrepancies: Where the flight's sources disagree with the logbook. Each marks the first
       of its fields that is shown, or else its first field, which is then shown explicitly.
   */
  init(
    flight: Flight,
    customFields: [CustomFieldDefinition],
    timeZone: TimeZone,
    changes: [FieldChange] = [],
    discrepancies: [SourceDiscrepancy] = []
  ) {
    let proposed = Self.applying(changes, to: flight)
    let touched = Set(
      changes.filter { $0.recordID == flight.id && $0.field.entity == .flight }.map(\.field)
    )
    let catalog = DetailCatalog(
      flights: [flight, proposed],
      customFields: customFields,
      timeZone: timeZone
    )
    let unmarked = Self.sections(in: catalog, current: flight, proposed: proposed, pinned: touched)
    let shownFields = Set(unmarked.flatMap(\.items).compactMap(\.field))
    let marks = Self.marks(for: discrepancies, shownFields: shownFields)
    let hidden = Set(marks.keys).subtracting(shownFields)
    let shown =
      hidden.isEmpty
      ? unmarked
      : Self.sections(
        in: catalog,
        current: flight,
        proposed: proposed,
        pinned: touched.union(hidden)
      )
    sections = shown.map { $0.marking(marks) }
  }

  private static func applying(_ changes: [FieldChange], to flight: Flight) -> Flight {
    changes.filter { $0.recordID == flight.id && $0.field.entity == .flight }
      .reduce(into: flight) { proposed, change in
        let knownPlaces = [flight.from, flight.to].compactMap(\.self)
        switch change.field {
          case .flightFrom: proposed.from = place(change.new, among: knownPlaces)
          case .flightTo: proposed.to = place(change.new, among: knownPlaces)
          default: proposed[field: change.field] = change.new
        }
      }
  }

  /// The place a From or To change names by its identifier: one of the flight's own places if
  /// it names one, otherwise a place known only by that identifier.
  private static func place(_ value: FieldValue, among known: [Place]) -> Place? {
    guard let identifier = value.text, !identifier.isEmpty else { return nil }
    return known.first { $0.preferredIdentifier == identifier }
      ?? Place(id: RecordID(rawValue: "proposed:\(identifier)"), identifier: identifier)
  }

  private static func sections(
    in catalog: DetailCatalog,
    current: Flight,
    proposed: Flight,
    pinned: Set<LogTenFieldKey>
  ) -> [Section] {
    Section.Kind.allCases.map { kind in
      Section(
        kind: kind,
        items: catalog.descriptors(for: kind).compactMap {
          $0.item(current: current, proposed: proposed, pinned: pinned)
        }
      )
    }
    .filter { !$0.items.isEmpty }
  }

  /// The field each discrepancy marks: its first shown field, or else its first field.
  private static func marks(
    for discrepancies: [SourceDiscrepancy],
    shownFields: Set<LogTenFieldKey>
  ) -> [LogTenFieldKey: SourceDiscrepancy] {
    Dictionary(
      discrepancies.compactMap { discrepancy in
        (discrepancy.fields.first(where: shownFields.contains) ?? discrepancy.fields.first)
          .map { ($0, discrepancy) }
      }
    ) { first, _ in first }
  }

  /// A group of details.
  struct Section: Identifiable {
    let kind: Kind
    let items: [Item]

    var id: Kind { kind }

    /// The section with each item that shows a discrepancy's field carrying it.
    func marking(_ marks: [LogTenFieldKey: SourceDiscrepancy]) -> Self {
      Self(
        kind: kind,
        items: items.map { item in
          var item = item
          item.discrepancy = item.field.flatMap { marks[$0] }
          return item
        }
      )
    }

    /// LogTen's inspector sections.
    enum Kind: CaseIterable {
      case flight, time, duty, crew, landings, operations, passengers, notes

      var title: String {
        switch self {
          case .flight: String(localized: "Flight")
          case .time: String(localized: "Time")
          case .duty: String(localized: "Duty")
          case .crew: String(localized: "Crew")
          case .landings: String(localized: "Landings")
          case .operations: String(localized: "Operations")
          case .passengers: String(localized: "Passengers")
          case .notes: String(localized: "Notes")
        }
      }
    }
  }

  /// One labeled detail, with the value a correction would write when it differs.
  struct Item: Hashable {
    /// The detail's label; empty for a list entry such as a passenger.
    let label: String

    /// The logbook field the detail shows, if it is a single field.
    let field: LogTenFieldKey?

    /// The recorded value, one part per box; empty when unset.
    let value: [Value]

    /// The value after the correction; the same as ``value`` when the correction leaves it.
    let proposedValue: [Value]

    /// Where the flight's sources disagree with the logbook on the detail.
    var discrepancy: SourceDiscrepancy?

    /// Whether the correction changes the detail.
    var isChanged: Bool { value != proposedValue }

    /// The number of boxes the detail shows.
    var partCount: Int { max(1, value.count, proposedValue.count) }
  }

  /// One box's text, with a qualifier such as a time zone.
  struct Value: Hashable {
    /// The value's text.
    let text: String

    /// What the value is reckoned in, such as `UTC` or `PST`.
    var qualifier: String?
  }
}

/// What each section shows of a flight, as labeled readings of it.
nonisolated private struct DetailCatalog {
  let flights: [Flight]
  let customFields: [CustomFieldDefinition]
  let timeZone: TimeZone

  private var flightDescriptors: [DetailDescriptor] {
    let timeZone = timeZone
    return [
      DetailDescriptor(label: String(localized: "Date"), field: .flightDate) { flight in
        [FlightDetails.Value(text: LogbookFormat.date(flight.date, in: timeZone))]
      },
      DetailDescriptor(label: String(localized: "Aircraft ID")) { flight in
        DetailDescriptor.text(flight.aircraft?.registration)
      },
      DetailDescriptor(label: String(localized: "Aircraft Type")) { flight in
        DetailDescriptor.text(flight.aircraft?.type?.type)
      },
      DetailDescriptor(label: String(localized: "From"), field: .flightFrom) { flight in
        DetailDescriptor.text(flight.from?.preferredIdentifier)
      },
      DetailDescriptor(label: String(localized: "To"), field: .flightTo) { flight in
        DetailDescriptor.text(flight.to?.preferredIdentifier)
      },
      field(.flightRoute),
      time(.flightActualDepartureTime, at: \.from),
      time(.flightTakeoffTime, at: \.from),
      time(.flightLandingTime, at: \.to),
      time(.flightActualArrivalTime, at: \.to),
      DetailDescriptor(
        label: title(of: .flightDistance),
        field: .flightDistance,
        value: { DetailDescriptor.text(Self.distanceText($0)) },
        explicitValue: { DetailDescriptor.text(Self.distanceText($0, explicit: true)) }
      ),
      field(.flightNumber)
    ]
  }

  private var timeDescriptors: [DetailDescriptor] {
    [
      .flightTotalTime, .flightPIC, .flightSIC, .flightSolo, .flightNight, .flightCrossCountry,
      .flightActualInstrument, .flightSimulatedInstrument, .flightSimulator, .flightDualGiven,
      .flightDualReceived, .flightGround, .flightNightVisionGoggle, .flightPICNight,
      .flightSICNight, .flightDualReceivedNight, .flightCrossCountryNight, .flightP1US,
      .flightP1USNight, .flightHobbsStart, .flightHobbsStop, .flightTachStart, .flightTachStop
    ]
    .map(field)
  }

  private var dutyDescriptors: [DetailDescriptor] {
    [time(.flightOnDutyTime, at: \.from), time(.flightOffDutyTime, at: \.to)]
  }

  private var crewDescriptors: [DetailDescriptor] {
    let positions: [(String, KeyPath<FlightCrew, Person?>)] = [
      (String(localized: "PIC"), \.PIC),
      (String(localized: "SIC"), \.SIC),
      (String(localized: "Instructor"), \.instructor),
      (String(localized: "Student"), \.student),
      (String(localized: "Flight Engineer"), \.flightEngineer),
      (String(localized: "Commander"), \.commander),
      (String(localized: "Purser"), \.purser)
    ]
    let groups: [(String, KeyPath<FlightCrew, [Person]>)] = [
      (String(localized: "Observer"), \.observers),
      (String(localized: "Relief"), \.relief),
      (String(localized: "Flight Attendant"), \.flightAttendants)
    ]
    return positions.map { label, path in
      DetailDescriptor(label: label) { DetailDescriptor.text($0.crew[keyPath: path]?.name) }
    }
      + groups.flatMap { label, path in
        listEntries(label: label) { $0.crew[keyPath: path].map(\.name) }
      }
  }

  private var landingDescriptors: [DetailDescriptor] {
    [
      .flightDayTakeoffs, .flightDayLandings, .flightNightTakeoffs, .flightNightLandings,
      .flightFullStops, .flightNightVisionGoggleTakeoffs, .flightNightVisionGoggleLandings
    ]
    .map(field)
  }

  private var operationDescriptors: [DetailDescriptor] {
    [field(.flightHolds)]
      + listEntries(label: String(localized: "Approach")) { $0.approaches.map(Self.approachText) }
      + [field(.flightReview), field(.flightInstrumentProficiencyCheck)]
  }

  private var passengerDescriptors: [DetailDescriptor] {
    listEntries(label: "") { $0.passengers.map(\.name) }
  }

  private static func distanceText(_ flight: Flight, explicit: Bool = false) -> String? {
    guard let distance = flight.distance, explicit || distance.value != 0 else { return nil }
    return LogbookFormat.distance(distance)
  }

  private static func approachText(_ approach: Approach) -> String {
    let name = approach.type?.rawValue ?? String(localized: "Approach")
    let location = [approach.place?.preferredIdentifier, approach.runway.map { "RWY \($0)" }]
      .compactMap(\.self).joined(separator: " ")
    let description = [name, location].filter { !$0.isEmpty }.joined(separator: " ")
    guard approach.count > 1 else { return description }
    return String(localized: "\(description) ×\(approach.count, format: .number)")
  }

  private static func text(
    for slot: CustomFieldSlot,
    in flight: Flight,
    explicit: Bool = false
  ) -> String? {
    if slot.kind == .flightCrew, let person = flight.crew.custom[slot.number] {
      return person.name
    }
    return LogbookFormat.value(flight[field: slot.key], as: slot.kind.valueKind, explicit: explicit)
  }

  private static func section(for kind: CustomFieldKind) -> FlightDetails.Section.Kind {
    switch kind {
      case .flightTime: .time
      case .flightLanding, .flightTakeoff: .landings
      case .flightOperation: .operations
      case .flightCapacity, .flightCrew: .crew
      default: .notes
    }
  }

  func descriptors(for kind: FlightDetails.Section.Kind) -> [DetailDescriptor] {
    switch kind {
      case .flight: flightDescriptors
      case .time: timeDescriptors + custom(in: .time)
      case .duty: dutyDescriptors
      case .crew: crewDescriptors + custom(in: .crew)
      case .landings: landingDescriptors + custom(in: .landings)
      case .operations: operationDescriptors + custom(in: .operations)
      case .passengers: passengerDescriptors
      case .notes: [field(.flightRemarks)] + custom(in: .notes)
    }
  }

  private func title(of field: LogTenFieldKey) -> String {
    LogbookFormat.fieldTitle(field, customFields: customFields)
  }

  private func field(_ key: LogTenFieldKey) -> DetailDescriptor {
    DetailDescriptor(
      label: title(of: key),
      field: key,
      value: { DetailDescriptor.text(LogbookFormat.detailValue($0[field: key], of: key)) },
      explicitValue: {
        DetailDescriptor.text(LogbookFormat.detailValue($0[field: key], of: key, explicit: true))
      }
    )
  }

  private func time(_ key: LogTenFieldKey, at place: KeyPath<Flight, Place?>) -> DetailDescriptor {
    let pilotZone = timeZone
    return DetailDescriptor(label: title(of: key), field: key) { flight in
      guard case .date(let date) = flight[field: key] else { return [] }
      let zone =
        flight[keyPath: place]?.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? pilotZone
      return [
        FlightDetails.Value(
          text: LogbookFormat.clockTime(date, in: .gmt),
          qualifier: String(localized: "UTC")
        ),
        FlightDetails.Value(
          text: LogbookFormat.clockTime(date, in: zone),
          qualifier: LogbookFormat.zoneName(zone, at: date)
        )
      ]
    }
  }

  /// One descriptor per entry of a list the flights hold, such as their observers.
  private func listEntries(
    label: String,
    entries: @escaping (Flight) -> [String]
  ) -> [DetailDescriptor] {
    let count = flights.map { entries($0).count }.max() ?? 0
    return (0..<count).map { index in
      DetailDescriptor(label: label) { flight in
        let names = entries(flight)
        return DetailDescriptor.text(names.indices.contains(index) ? names[index] : nil)
      }
    }
  }

  private func custom(in section: FlightDetails.Section.Kind) -> [DetailDescriptor] {
    let titles = Dictionary(customFields.map { ($0.key, $0.title) }) { first, _ in first }
    return Set(flights.flatMap { $0.customValues.keys.compactMap(\.customSlot) })
      .filter { Self.section(for: $0.kind) == section }
      .sorted { ($0.kind.rawValue, $0.number) < ($1.kind.rawValue, $1.number) }
      .map { slot in
        DetailDescriptor(
          label: titles[slot.key] ?? slot.key.rawValue,
          field: slot.key,
          value: { DetailDescriptor.text(Self.text(for: slot, in: $0)) },
          explicitValue: { DetailDescriptor.text(Self.text(for: slot, in: $0, explicit: true)) }
        )
      }
  }
}

/// A labeled reading of a flight, which yields a detail item when either flight has a value.
nonisolated private struct DetailDescriptor {
  let label: String
  let field: LogTenFieldKey?
  let value: (Flight) -> [FlightDetails.Value]

  /// The reading of a detail a correction touches, if it differs from ``value``; it shows the
  /// zeros and falses that ``value`` leaves blank.
  let explicitValue: ((Flight) -> [FlightDetails.Value])?

  init(
    label: String,
    field: LogTenFieldKey? = nil,
    value: @escaping (Flight) -> [FlightDetails.Value],
    explicitValue: ((Flight) -> [FlightDetails.Value])? = nil
  ) {
    self.label = label
    self.field = field
    self.value = value
    self.explicitValue = explicitValue
  }

  /// A single-box value, or none when the text is missing or empty.
  static func text(_ text: String?) -> [FlightDetails.Value] {
    guard let text, !text.isEmpty else { return [] }
    return [FlightDetails.Value(text: text)]
  }

  /// The detail for a flight and its corrected self, or `nil` if neither has a value and
  /// `pinned`, the fields always shown with explicit values, doesn't hold the detail's field.
  func item(current: Flight, proposed: Flight, pinned: Set<LogTenFieldKey>) -> FlightDetails.Item? {
    let isPinned = field.map(pinned.contains) ?? false
    let reading = isPinned ? (explicitValue ?? value) : value
    let currentValue = reading(current)
    let proposedValue = reading(proposed)
    guard isPinned || !currentValue.isEmpty || !proposedValue.isEmpty else { return nil }
    return FlightDetails.Item(
      label: label,
      field: field,
      value: currentValue,
      proposedValue: proposedValue
    )
  }
}
