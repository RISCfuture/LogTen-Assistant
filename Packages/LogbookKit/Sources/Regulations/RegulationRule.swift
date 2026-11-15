public import LogbookModel

/// The regulations the violation checkers enforce.
public enum RegulationRule: String, CaseIterable, Codable, Sendable {
  /// Acting as pilot in command without a flight review in the preceding 24 calendar months
  /// (14 CFR 61.56(c)). Dual received, student solo and practical tests are exempt.
  case noFlightReview = "no_flight_review"

  /// Carrying passengers without three takeoffs and landings in the category, class and, if a
  /// type rating is required, type within the preceding 90 days (14 CFR 61.57(a)); full-stop
  /// landings in a tailwheel airplane.
  case noPassengerCurrency = "no_passenger_currency"

  /// Carrying passengers at night without three night takeoffs and full-stop landings within the
  /// preceding 90 days (14 CFR 61.57(b)).
  case noNightPassengerCurrency = "no_night_passenger_currency"

  /// Acting as pilot in command under IFR without six approaches, holding and intercepting and
  /// tracking courses within the preceding six calendar months, or an instrument proficiency
  /// check (14 CFR 61.57(c) and (d)).
  case noIFRCurrency = "no_iFRCurrency"

  /// Acting as pilot in command of a type-rated aircraft without a proficiency check within the
  /// preceding 12 calendar months (14 CFR 61.58(a)(1)).
  case noProficiencyCheck = "no_proficiency_check"

  /// Acting as pilot in command of a type-rated aircraft without a proficiency check in that
  /// type within the preceding 24 calendar months (14 CFR 61.58(a)(2)).
  case noProficiencyCheckInType = "no_proficiency_check_in_type"

  /// Acting as pilot in command using night-vision goggles without the required recent NVG
  /// experience or a proficiency check (14 CFR 61.57(f)).
  case noNVGCurrency = "no_nVGCurrency"

  /// Carrying passengers using night-vision goggles without the required recent NVG experience
  /// or a proficiency check (14 CFR 61.57(f)).
  case noNVGPassengerCurrency = "no_nVGPassenger_currency"

  /// Giving more than eight hours of flight training in any 24 consecutive hours
  /// (14 CFR 61.195(a)).
  case dualGiven8In24 = "dual_given_8_in_24"

  /// Giving flight training in a multi-engine airplane, helicopter or powered lift without five
  /// hours as pilot in command in that make and model (14 CFR 61.195(f)).
  case dualGivenTimeInType = "dual_given_time_in_type"

  /// Serving as second in command of a type-rated aircraft without three takeoffs and landings
  /// in type within the preceding 90 days (14 CFR 61.55(b)).
  case noSICCurrency = "no_sICCurrency"

  /// The rule's identifier in findings and settings.
  public var id: RuleID { RuleID(rawValue: "regulation.\(rawValue)") }

  /// The regulation the rule enforces.
  public var citation: String {
    switch self {
      case .noFlightReview: "14 CFR 61.56(c)"
      case .noPassengerCurrency: "14 CFR 61.57(a)"
      case .noNightPassengerCurrency: "14 CFR 61.57(b)"
      case .noIFRCurrency: "14 CFR 61.57(c)"
      case .noProficiencyCheck: "14 CFR 61.58(a)(1)"
      case .noProficiencyCheckInType: "14 CFR 61.58(a)(2)"
      case .noNVGCurrency, .noNVGPassengerCurrency: "14 CFR 61.57(f)"
      case .dualGiven8In24: "14 CFR 61.195(a)"
      case .dualGivenTimeInType: "14 CFR 61.195(f)"
      case .noSICCurrency: "14 CFR 61.55(b)"
    }
  }
}
