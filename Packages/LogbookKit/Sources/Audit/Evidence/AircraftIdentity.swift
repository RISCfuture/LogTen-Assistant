public import LogbookModel

/// Resolves the different names an aircraft appears under to one registration.
///
/// FlySto, ADS-B archives and the logbook may name the same aircraft differently (a former
/// registration, a hex address, a nickname). Each aircraft's
/// `AircraftSettings.aliases` list the other names, and names compare case-insensitively.
public struct AircraftIdentity: Sendable {
  private let canonicalNames: [String: String]

  /// Creates an identity resolver from per-aircraft settings keyed by registration.
  public init(settings: [String: AircraftSettings] = [:]) {
    var names = [String: String]()
    for (registration, aircraft) in settings {
      let canonical = registration.uppercased()
      names[canonical] = canonical
      for alias in aircraft.aliases { names[alias.uppercased()] = canonical }
    }
    canonicalNames = names
  }

  /// The registration an aircraft is known by, uppercased; unknown names resolve to
  /// themselves.
  public func canonicalName(_ name: String) -> String {
    let uppercased = name.uppercased()
    return canonicalNames[uppercased] ?? uppercased
  }

  /// Whether two names are the same aircraft; missing or empty names never are.
  public func isSame(_ first: String?, _ second: String?) -> Bool {
    guard let first, let second, !first.isEmpty, !second.isEmpty else { return false }
    return canonicalName(first) == canonicalName(second)
  }
}
