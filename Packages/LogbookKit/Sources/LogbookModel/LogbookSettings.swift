public import Foundation

/// Everything the app knows about one logbook that the logbook itself doesn't record.
///
/// Settings are stored per logbook, keyed by its store UUID, in the logbook's workspace.
public struct LogbookSettings: Hashable, Codable, Sendable {
  /// The pilot whose logbook it is.
  public var pilot: PilotProfile

  /// Which fields hold the roles the checks need.
  public var fieldMapping: FieldMapping

  /// Per-aircraft settings, keyed by registration.
  public var aircraft: [String: AircraftSettings]

  /// Rule configuration.
  public var rules: RuleSettings

  /// Creates logbook settings.
  public init(
    pilot: PilotProfile = .init(),
    fieldMapping: FieldMapping = .init(),
    aircraft: [String: AircraftSettings] = [:],
    rules: RuleSettings = .init()
  ) {
    self.pilot = pilot
    self.fieldMapping = fieldMapping
    self.aircraft = aircraft
    self.rules = rules
  }

  /// The settings for an aircraft, or the defaults if it has none.
  public func settings(forAircraft registration: String) -> AircraftSettings {
    aircraft[registration] ?? .init()
  }
}

/// Which rules run and how they are tuned for one logbook.
///
/// Most rules run unless turned off; a rule that is off by default runs only once turned on.
public struct RuleSettings: Hashable, Codable, Sendable {
  /// Rules on by default that the user has turned off.
  public var disabledRules: Set<RuleID>

  /// Rules off by default that the user has turned on.
  public var enabledRules: Set<RuleID>

  /// User-defined consistency rules between flight fields.
  public var customRules: [CustomRule]

  /// Place identifiers that are deliberately not airports, such as a private strip or a lake.
  public var nonAirportPlaces: Set<String>

  /// Currency events the logbook doesn't show but the pilot has confirmed, such as an IPC
  /// logged elsewhere.
  public var confirmedCurrencyEvents: [ConfirmedCurrencyEvent]

  /// Matching and plausibility tolerances.
  public var tolerances: AuditTolerances

  /// Creates rule settings.
  public init(
    disabledRules: Set<RuleID> = [],
    enabledRules: Set<RuleID> = [],
    customRules: [CustomRule] = [],
    nonAirportPlaces: Set<String> = [],
    confirmedCurrencyEvents: [ConfirmedCurrencyEvent] = [],
    tolerances: AuditTolerances = .init()
  ) {
    self.disabledRules = disabledRules
    self.enabledRules = enabledRules
    self.customRules = customRules
    self.nonAirportPlaces = nonAirportPlaces
    self.confirmedCurrencyEvents = confirmedCurrencyEvents
    self.tolerances = tolerances
  }

  /// Decodes rule settings; a missing set of enabled rules decodes as empty.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    disabledRules = try container.decode(Set<RuleID>.self, forKey: .disabledRules)
    enabledRules = try container.decodeIfPresent(Set<RuleID>.self, forKey: .enabledRules) ?? []
    customRules = try container.decode([CustomRule].self, forKey: .customRules)
    nonAirportPlaces = try container.decode(Set<String>.self, forKey: .nonAirportPlaces)
    confirmedCurrencyEvents = try container.decode(
      [ConfirmedCurrencyEvent].self,
      forKey: .confirmedCurrencyEvents
    )
    tolerances = try container.decode(AuditTolerances.self, forKey: .tolerances)
  }

  /**
   Whether a rule runs.

   - Parameters:
     - rule: The rule.
     - byDefault: Whether the rule runs when the user hasn't turned it on or off.
   */
  public func isEnabled(_ rule: RuleID, byDefault: Bool = true) -> Bool {
    byDefault ? !disabledRules.contains(rule) : enabledRules.contains(rule)
  }

  /**
   Turns a rule on or off.

   - Parameters:
     - isEnabled: Whether the rule should run.
     - rule: The rule.
     - byDefault: Whether the rule runs when the user hasn't turned it on or off.
   */
  public mutating func setEnabled(_ isEnabled: Bool, _ rule: RuleID, byDefault: Bool = true) {
    if byDefault {
      if isEnabled { disabledRules.remove(rule) } else { disabledRules.insert(rule) }
    } else {
      if isEnabled { enabledRules.insert(rule) } else { enabledRules.remove(rule) }
    }
  }

  private enum CodingKeys: String, CodingKey {
    case disabledRules, enabledRules, customRules, nonAirportPlaces, confirmedCurrencyEvents
    case tolerances
  }
}

/// A user-defined consistency rule between flight fields.
public struct CustomRule: Identifiable, Hashable, Codable, Sendable {
  /// The rule's identifier, unique within the logbook.
  public var id: RuleID

  /// What the rule checks.
  public var kind: Kind

  /// The field the rule checks.
  public var field: LogTenFieldKey

  /// The field it is checked against, for ``Kind/subset`` and ``Kind/requires``.
  public var other: LogTenFieldKey?

  /// The severity of findings the rule produces.
  public var severity: Severity

  /// Creates a custom rule.
  public init(
    id: RuleID,
    kind: Kind,
    field: LogTenFieldKey,
    other: LogTenFieldKey? = nil,
    severity: Severity = .suggestion
  ) {
    self.id = id
    self.kind = kind
    self.field = field
    self.other = other
    self.severity = severity
  }

  /// The kinds of custom rule.
  public enum Kind: String, CaseIterable, Codable, Sendable {
    /// `field` must not exceed `other`, as night time must not exceed total time.
    case subset
    /// `field` must not be negative.
    case nonnegative
    /// When `field` is set, `other` must be set too.
    case requires
  }
}

/// A currency event the pilot has confirmed outside the logbook.
public struct ConfirmedCurrencyEvent: Hashable, Codable, Sendable {
  /// The day of the event, in the pilot's home time zone.
  public var date: DateComponents

  /// What happened.
  public var kind: Kind

  /// The aircraft category the event applies to, if it is category-specific.
  public var category: AircraftCategory?

  /// The pilot's note about the event.
  public var note: String?

  /// Creates a confirmed event.
  public init(
    date: DateComponents,
    kind: Kind,
    category: AircraftCategory? = nil,
    note: String? = nil
  ) {
    self.date = date
    self.kind = kind
    self.category = category
    self.note = note
  }

  /// The kinds of confirmed event.
  public enum Kind: String, CaseIterable, Codable, Sendable {
    /// A flight review (14 CFR 61.56).
    case flightReview = "flight_review"
    /// An instrument proficiency check (14 CFR 61.57(d)).
    case instrumentProficiencyCheck = "instrument_proficiency_check"
    /// An instrument rating practical test, which starts instrument currency.
    case instrumentRating = "instrument_rating"
    /// A pilot-in-command proficiency check (14 CFR 61.58).
    case proficiencyCheck = "proficiency_check"
  }
}

/// Matching and plausibility tolerances for audits.
public struct AuditTolerances: Hashable, Codable, Sendable {
  /// How far apart two times may be and still agree, in minutes.
  public var timeToleranceMinutes: UInt

  /// How close two entries' times must be to count as duplicates, in minutes.
  public var duplicateTimeMinutes: UInt

  /// The longest plausible flight for an aircraft without its own limit, in minutes.
  public var maximumFlightMinutes: UInt

  /// Creates tolerances; the defaults match cleanup-logten's.
  public init(
    timeToleranceMinutes: UInt = 6,
    duplicateTimeMinutes: UInt = 5,
    maximumFlightMinutes: UInt = 18 * 60
  ) {
    self.timeToleranceMinutes = timeToleranceMinutes
    self.duplicateTimeMinutes = duplicateTimeMinutes
    self.maximumFlightMinutes = maximumFlightMinutes
  }
}
