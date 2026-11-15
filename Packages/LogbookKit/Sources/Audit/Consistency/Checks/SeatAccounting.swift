import Foundation
import LogbookModel

/// A seat or training role whose time a flight logs, in the order Flight Audit lists them.
enum SeatRole: CaseIterable {
  case pic
  case sic
  case p1us
  case dualReceived

  /// The attribute name, such as `dualReceived`.
  var fieldName: String {
    switch self {
      case .pic: "pic"
      case .sic: "sic"
      case .p1us: "p1us"
      case .dualReceived: "dualReceived"
    }
  }

  /// The attribute name of the role's night time, such as `dualReceivedNight`.
  var nightFieldName: String { fieldName + "Night" }

  /// The lowercased attribute holding the role's time.
  var attribute: String { fieldName.lowercased() }

  /// The lowercased attribute holding the role's night time.
  var nightAttribute: String { nightFieldName.lowercased() }

  /// The name the role is shown by.
  var title: String {
    switch self {
      case .pic: String(localized: "PIC", bundle: .module)
      case .sic: String(localized: "SIC", bundle: .module)
      case .p1us: String(localized: "P1 u/s", bundle: .module)
      case .dualReceived: String(localized: "Dual Received", bundle: .module)
    }
  }

  /// The name the role’s night time is shown by.
  var nightTitle: String {
    String(localized: "\(title) Night", bundle: .module)
  }
}

/**
 How a flight's role times share its time, the arithmetic Seat Time and Night Seat Time use.

 US pilots log several roles for the same minutes. A pilot in command who is receiving
 instruction logs the whole period as both PIC and dual received; a solo flight is PIC time; and
 dual given is PIC time. Counting those as separate periods would flag ordinary logbooks. The
 roles that cannot share a minute are the seats themselves: PIC, SIC and P1 u/s, which are
 different positions on the flight deck.

 So the time the roles occupy is the longest of the PIC-level roles (PIC, dual received, solo
 and dual given, each of which can be the same period as PIC) plus SIC plus P1 u/s. A PIC and an
 SIC that each fill the flight occupy twice its time, which Flight Audit flags, while PIC and
 dual received that each fill it occupy it once and raise nothing.
 */
struct SeatAccounting {
  private let minutes: [SeatRole: UInt]
  private let commandAdjacent: UInt

  /// The longest of the roles that may share the PIC's minutes.
  var commandLevel: UInt {
    max(minutes(.pic), minutes(.dualReceived), commandAdjacent)
  }

  /// The minutes the roles occupy when each seat has its own period.
  var occupied: UInt { commandLevel + minutes(.sic) + minutes(.p1us) }

  /// The roles that log time, in listing order.
  var loggedRoles: [SeatRole] { SeatRole.allCases.filter { minutes($0) > 0 } }

  /// Whether no role, solo or dual given logs any time.
  var isEmpty: Bool { occupied == 0 }

  /// The accounting of a flight's total-time roles.
  init(_ flight: AuditedFlight) {
    self.init(
      minutes: Self.minutes(of: flight, \.attribute),
      commandAdjacent: max(Self.minutes(flight, "solo"), Self.minutes(flight, "dualgiven"))
    )
  }

  /// The accounting of a flight's night roles.
  init(nightOf flight: AuditedFlight) {
    self.init(minutes: Self.minutes(of: flight, \.nightAttribute), commandAdjacent: 0)
  }

  private init(minutes: [SeatRole: UInt], commandAdjacent: UInt) {
    self.minutes = minutes
    self.commandAdjacent = commandAdjacent
  }

  private static func minutes(
    of flight: AuditedFlight,
    _ attribute: KeyPath<SeatRole, String>
  ) -> [SeatRole: UInt] {
    Dictionary(
      uniqueKeysWithValues: SeatRole.allCases.map { ($0, minutes(flight, $0[keyPath: attribute])) }
    )
  }

  private static func minutes(_ flight: AuditedFlight, _ name: String) -> UInt {
    UInt(max(0, flight.number(name) ?? 0))
  }

  /// The minutes a role logs.
  func minutes(_ role: SeatRole) -> UInt { minutes[role] ?? 0 }

  /// The accounting with each role's time limited to a ceiling.
  func limited(_ ceiling: (SeatRole) -> UInt) -> Self {
    Self(
      minutes: Dictionary(
        uniqueKeysWithValues: SeatRole.allCases.map { ($0, min(minutes($0), ceiling($0))) }
      ),
      commandAdjacent: commandAdjacent
    )
  }

  /// The accounting without one role.
  func removing(_ role: SeatRole) -> Self {
    Self(minutes: minutes.filter { $0.key != role }, commandAdjacent: commandAdjacent)
  }
}
