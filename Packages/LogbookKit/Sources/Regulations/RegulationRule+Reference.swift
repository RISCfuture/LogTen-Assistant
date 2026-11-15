public import Foundation
public import LogbookModel

extension RegulationRule {
  /// A short name for the rule, for lists and sidebars.
  public var title: String {
    switch self {
      case .noFlightReview: String(localized: "Flight Review", bundle: .module)
      case .noPassengerCurrency: String(localized: "Passenger Currency", bundle: .module)
      case .noNightPassengerCurrency:
        String(localized: "Night Passenger Currency", bundle: .module)
      case .noIFRCurrency: String(localized: "IFR Currency", bundle: .module)
      case .noProficiencyCheck: String(localized: "Proficiency Check", bundle: .module)
      case .noProficiencyCheckInType:
        String(localized: "Proficiency Check in Type", bundle: .module)
      case .noNVGCurrency: String(localized: "NVG Currency", bundle: .module)
      case .noNVGPassengerCurrency: String(localized: "NVG Passenger Currency", bundle: .module)
      case .dualGiven8In24: String(localized: "Instruction Limit", bundle: .module)
      case .dualGivenTimeInType: String(localized: "Instructor Time in Type", bundle: .module)
      case .noSICCurrency: String(localized: "SIC Currency", bundle: .module)
    }
  }

  /// What the rule can't see in a logbook, in a sentence or two, or `nil` if nothing worth
  /// noting.
  public var limitations: String? {
    switch self {
      case .noFlightReview:
        String(
          localized: """
            Flights before your first checkride aren’t checked, since a flight review is needed \
            only once you hold a certificate.
            """,
          bundle: .module
        )
      case .noPassengerCurrency, .noNightPassengerCurrency:
        String(
          localized: """
            Days are counted in your home time zone. Legs logged as one flight are checked as one, \
            so landings on an earlier leg don’t count for passengers on a later one.
            """,
          bundle: .module
        )
      case .noIFRCurrency:
        String(
          localized: """
            Only flights with actual instrument time count as IFR, so IFR flights in visual \
            conditions aren’t checked. Intercepting and tracking courses is assumed on flights \
            with approaches unless a field records it.
            """,
          bundle: .module
        )
      case .noNVGCurrency, .noNVGPassengerCurrency:
        String(
          localized: "Only NVG takeoffs and landings are checked, not hovering or other NVG tasks.",
          bundle: .module
        )
      case .noProficiencyCheck, .noProficiencyCheckInType, .dualGiven8In24,
        .dualGivenTimeInType, .noSICCurrency:
        nil
    }
  }

  /// The Part 61 section the rule enforces, such as `61.57`.
  public var section: String {
    switch self {
      case .noFlightReview: "61.56"
      case .noPassengerCurrency, .noNightPassengerCurrency, .noIFRCurrency, .noNVGCurrency,
        .noNVGPassengerCurrency:
        "61.57"
      case .noProficiencyCheck, .noProficiencyCheckInType: "61.58"
      case .dualGiven8In24, .dualGivenTimeInType: "61.195"
      case .noSICCurrency: "61.55"
    }
  }

  /// The regulation's text in the Electronic Code of Federal Regulations.
  public var citationURL: URL {
    let subpart = section == "61.195" ? "subpart-H" : "subpart-A"
    return URL(
      string:
        "https://www.ecfr.gov/current/title-14/chapter-I/subchapter-D/part-61/\(subpart)/section-\(section)"
    )!
  }

  /// The field roles the rule reads. The rule can't be evaluated until each is mapped.
  public var requiredRoles: [FieldRole] {
    switch self {
      case .noFlightReview: [.checkride]
      case .noNightPassengerCurrency: [.nightTakeoffs, .nightFullStops]
      case .noIFRCurrency: [.safetyPilot]
      case .noProficiencyCheck, .noProficiencyCheckInType: [.proficiencyCheck]
      case .noNVGCurrency, .noNVGPassengerCurrency: [.nightVisionGoggleProficiencyCheck]
      case .noPassengerCurrency, .dualGiven8In24, .dualGivenTimeInType, .noSICCurrency: []
    }
  }

  /// Whether the rule concerns only flight instructors.
  public var isInstructorRule: Bool {
    self == .dualGiven8In24 || self == .dualGivenTimeInType
  }
}
