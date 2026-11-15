import LogbookModel

/**
 Whether the pilot usually records something on entries like a given one, learned from the
 logbook: “on flights like this that log Y, do you usually fill in X?”

 A habit is learned once over every flight, grouped by ``FlightSimilarity``, and then asked
 about each flight. The flight asked about is left out of its own sample, so an omission isn't
 excused by itself. A habit holds only when enough similar flights log Y and nearly all of them
 fill in X; otherwise nothing is assumed, and a habit-aware check stays quiet.

 ```swift
 let namesPIC = FlightHabit(
   over: context.flights,
   similarity: .aircraftType,
   when: { $0.hasPositive("sic") },
   records: { $0.flight.crew.PIC != nil }
 )
 for flight in context.flights where flight.hasPositive("sic") && flight.flight.crew.PIC == nil {
   if namesPIC.isUsual(for: flight) { … }
 }
 ```
 */
struct FlightHabit {
  /// The share of similar flights that must record something for it to count as a habit.
  static let usualShare = 0.8

  /// The fewest similar flights, besides the one asked about, a habit is learned from.
  static let minimumSampleSize = 5

  private let similarity: FlightSimilarity
  private let applies: (AuditedFlight) -> Bool
  private let records: (AuditedFlight) -> Bool
  private let tallies: [FlightSimilarity.Key: Tally]

  /**
   Learns a habit.

   - Parameters:
     - flights: The flights to learn from, normally every flight of the logbook.
     - similarity: Which flights count as like one another.
     - applies: Whether a flight logs what the habit is about, such as SIC time.
     - records: Whether a flight records what the pilot may habitually record, such as a PIC
       name.
   */
  init(
    over flights: [AuditedFlight],
    similarity: FlightSimilarity,
    when applies: @escaping (AuditedFlight) -> Bool,
    records: @escaping (AuditedFlight) -> Bool
  ) {
    self.similarity = similarity
    self.applies = applies
    self.records = records
    var tallies = [FlightSimilarity.Key: Tally]()
    for flight in flights where applies(flight) {
      tallies[similarity.key(for: flight), default: Tally()].count(records(flight))
    }
    self.tallies = tallies
  }

  /// Whether the pilot usually records it on flights like this one that it applies to.
  func isUsual(for flight: AuditedFlight) -> Bool {
    var tally = tallies[similarity.key(for: flight)] ?? Tally()
    if applies(flight) { tally.uncount(records(flight)) }
    return tally.total >= Self.minimumSampleSize
      && Double(tally.recorded) >= Self.usualShare * Double(tally.total)
  }

  private struct Tally {
    var total = 0
    var recorded = 0

    mutating func count(_ isRecorded: Bool) {
      total += 1
      if isRecorded { recorded += 1 }
    }

    mutating func uncount(_ isRecorded: Bool) {
      total -= 1
      if isRecorded { recorded -= 1 }
    }
  }
}

/// Which flights a ``FlightHabit`` treats as like one another: those sharing every chosen
/// trait. With no traits chosen, every flight is like every other.
struct FlightSimilarity: OptionSet, Hashable {
  /// The role times a flight's role pattern is made of, by lowercased attribute name.
  static let roleNames = ["pic", "sic", "dualgiven", "dualreceived", "solo", "p1us"]

  /// Flights in the same aircraft type.
  static let aircraftType = Self(rawValue: 1 << 0)

  /// Flights logging the same set of role times.
  static let roles = Self(rawValue: 1 << 1)

  let rawValue: Int

  /// The traits a flight shares with flights like it.
  func key(for flight: AuditedFlight) -> Key {
    Key(
      aircraftType: contains(.aircraftType) ? flight.flight.aircraft?.type?.id : nil,
      roles: contains(.roles) ? Set(Self.roleNames.filter(flight.hasPositive)) : nil
    )
  }

  /// What flights alike under a similarity share.
  struct Key: Hashable {
    var aircraftType: RecordID?
    var roles: Set<String>?
  }
}
