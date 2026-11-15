import Foundation

/**
 One way of resolving a finding: a named set of field changes the reviewer can choose, such as
 “Clear SIC” as an alternative to “Clear PIC”.

 An option's ``id`` is derived from its changes alone, so the same edits keep the same
 identifier from one audit run to the next however the option is titled, and a reviewer's
 choice carries forward while the option is still offered.
 */
public struct CorrectionOption: Identifiable, Hashable, Codable, Sendable {
  /// The content-addressed identifier.
  public let id: CorrectionOptionID

  /// A localized, short imperative title, such as “Clear SIC”.
  public var title: String

  /// A localized line spelling out the effect, such as “SIC becomes 0:00, leaving PIC as
  /// logged.”
  public var detail: String?

  /// The edits the option makes.
  public let changes: [FieldChange]

  /**
   Creates an option and derives its identifier.

   - Parameters:
     - title: A localized short imperative title.
     - detail: A localized line spelling out the effect.
     - changes: The edits the option makes.
   */
  public init(title: String, detail: String? = nil, changes: [FieldChange]) {
    id = CorrectionOptionID(changes: changes)
    self.title = title
    self.detail = detail
    self.changes = changes
  }
}

/// The content-addressed identifier of a ``CorrectionOption``: the first 20 hexadecimal digits
/// of the SHA-256 digest of the canonical JSON array of its changes.
public struct CorrectionOptionID: RawRepresentable, Hashable, Comparable, Codable, Sendable,
  CustomStringConvertible
{
  private static let length = 20

  public let rawValue: String

  public var description: String { rawValue }

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// Derives the identifier of a set of changes.
  public init(changes: [FieldChange]) {
    let digest = CanonicalJSON.sha256(of: .array(changes.map(\.canonicalJSON)))
    rawValue = String(digest.prefix(Self.length))
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Why a finding's corrections can only be made by hand in LogTen: a record they would change
/// can't be edited as it stands.
public enum CorrectionRestriction: String, Codable, Sendable {
  /// A flight is signed; unlocking it to make the change removes the signature.
  case signed
  /// A flight is locked against editing.
  case locked

  /// A localized explanation for the reviewer, including that approving adds the change to the
  /// checklist.
  public var explanation: String {
    switch self {
      case .signed:
        String(
          localized:
            "This flight is signed. Unlocking it in LogTen to change it removes the signature. Approving adds the change to the checklist of changes to make in LogTen yourself, after which the flight needs signing again.",
          bundle: .module
        )
      case .locked:
        String(
          localized:
            "This flight is locked. Approving adds the change to the checklist of changes to make in LogTen yourself, after unlocking the flight.",
          bundle: .module
        )
    }
  }

  /// The restriction for a set of flights: signed if any is signed, otherwise locked if any is
  /// locked, otherwise none.
  init?(protecting flights: some Sequence<Flight>) {
    let flights = Array(flights)
    if flights.contains(where: \.isSigned) {
      self = .signed
    } else if flights.contains(where: \.isLocked) {
      self = .locked
    } else {
      return nil
    }
  }
}
