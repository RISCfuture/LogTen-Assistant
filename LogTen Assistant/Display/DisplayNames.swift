import Foundation
import LogbookModel
import Regulations

nonisolated extension AuditPage {
  var title: String {
    switch self {
      case .dataSources: String(localized: "Data Sources")
      case .logbookConsistency: String(localized: "Logbook Consistency")
      case .aircraftComparisons: String(localized: "Aircraft Comparisons")
      case .unmatchedActivity: String(localized: "Unmatched Activity")
      case .groupsAndCurrency: String(localized: "Groups & Currency")
      case .approved: String(localized: "Approved")
      case .appliedHistory: String(localized: "Applied History")
    }
  }

  /// What the page will show, for its placeholder.
  var summary: String {
    switch self {
      case .dataSources:
        String(localized: "FlySto sync status, ADS-B downloads and coverage by aircraft and date.")
      case .logbookConsistency:
        String(localized: "Entries whose times, counts or references disagree with each other.")
      case .aircraftComparisons:
        String(localized: "Entries that disagree with FlySto or ADS-B evidence for the aircraft.")
      case .unmatchedActivity:
        String(localized: "Flights in FlySto or ADS-B data that no logbook entry accounts for.")
      case .groupsAndCurrency:
        String(localized: "Smart groups whose definitions don’t match the regulations they track.")
      case .approved:
        String(localized: "Fixes you approved, ready to back up and apply through LogTen.")
      case .appliedHistory:
        String(localized: "Batches applied to the logbook, with their verification and revert.")
    }
  }
}

nonisolated extension RuleStatus {
  /// Why a rule found nothing, or `nil` if it ran.
  var explanation: String? {
    switch self {
      case .evaluated: nil
      case .skipped(let reason): reason.explanation
      case .notEvaluated(let roles):
        String(
          localized:
            "This rule needs these fields mapped in Logbook Settings: \(roles.map(\.title).formatted(.list(type: .and)))."
        )
    }
  }
}

nonisolated extension RuleSkipReason {
  var explanation: String {
    switch self {
      case .disabled: String(localized: "This rule is turned off for the logbook.")
      case .notFlightInstructor:
        String(localized: "This rule applies only to flight instructors.")
      case .ignoresInstructionActivity:
        String(localized: "The pilot settings ignore instruction activity.")
      case .noInstrumentRating:
        String(localized: "This rule applies only to pilots with an instrument rating.")
      case .studentPilot: String(localized: "This rule doesn’t apply to student pilots.")
    }
  }
}

nonisolated extension FieldRole {
  var title: String {
    switch self {
      case .nightTakeoffs: String(localized: "Night Takeoffs")
      case .nightFullStops: String(localized: "Night Full-Stop Landings")
      case .atpCrossCountry: String(localized: "ATP Cross-Country")
      case .safetyPilot: String(localized: "Safety Pilot")
      case .examiner: String(localized: "Examiner")
      case .proficiencyCheck: String(localized: "61.58 Proficiency Check")
      case .checkride: String(localized: "Checkride")
      case .nightVisionGoggleProficiencyCheck: String(localized: "61.31(k) NVG Proficiency Check")
      case .interceptingAndTracking: String(localized: "Intercepting and Tracking")
      case .typeCode: String(localized: "Type Code")
      case .simulatorType: String(localized: "Simulator Type")
      case .simulatorCategoryClass: String(localized: "Simulator Category and Class")
    }
  }

  var summary: String {
    switch self {
      case .nightTakeoffs: String(localized: "Night takeoffs, for night passenger currency.")
      case .nightFullStops:
        String(localized: "Night full-stop landings, for night passenger currency.")
      case .atpCrossCountry: String(localized: "Cross-country time meeting the ATP definition.")
      case .safetyPilot: String(localized: "The crew role naming the safety pilot.")
      case .examiner: String(localized: "The crew role naming the examiner.")
      case .proficiencyCheck: String(localized: "Marks a 14 CFR 61.58 proficiency check.")
      case .checkride: String(localized: "Marks a practical test.")
      case .nightVisionGoggleProficiencyCheck:
        String(localized: "Marks a 14 CFR 61.31(k) night-vision-goggle proficiency check.")
      case .interceptingAndTracking:
        String(localized: "Marks intercepting and tracking courses for IFR currency.")
      case .typeCode:
        String(localized: "The ICAO type designator, when LogTen’s type identifier differs.")
      case .simulatorType: String(localized: "BATD, AATD, FTD or FFS.")
      case .simulatorCategoryClass:
        String(localized: "The category and class a simulator represents, such as ASEL.")
    }
  }

  /// The rules that can't run until the role is mapped.
  var dependentRules: [RegulationRule] {
    RegulationRule.allCases.filter { $0.requiredRoles.contains(self) }
  }
}

nonisolated extension CertificateLevel {
  var title: String {
    switch self {
      case .student: String(localized: "Student")
      case .sport: String(localized: "Sport")
      case .recreational: String(localized: "Recreational")
      case .private: String(localized: "Private")
      case .commercial: String(localized: "Commercial")
      case .airlineTransport: String(localized: "Airline Transport")
    }
  }
}

nonisolated extension CategoryClassRating {
  var title: String {
    switch self {
      case .airplaneSingleEngineLand: String(localized: "Airplane Single-Engine Land")
      case .airplaneSingleEngineSea: String(localized: "Airplane Single-Engine Sea")
      case .airplaneMultiEngineLand: String(localized: "Airplane Multi-Engine Land")
      case .airplaneMultiEngineSea: String(localized: "Airplane Multi-Engine Sea")
      case .glider: String(localized: "Glider")
      case .rotorcraftHelicopter: String(localized: "Rotorcraft Helicopter")
      case .rotorcraftGyroplane: String(localized: "Rotorcraft Gyroplane")
      case .lighterThanAirBalloon: String(localized: "Lighter-Than-Air Balloon")
      case .lighterThanAirAirship: String(localized: "Lighter-Than-Air Airship")
      case .poweredLift: String(localized: "Powered Lift")
    }
  }
}

nonisolated extension InstrumentRating {
  var title: String {
    switch self {
      case .airplane: String(localized: "Instrument Airplane")
      case .helicopter: String(localized: "Instrument Helicopter")
      case .poweredLift: String(localized: "Instrument Powered Lift")
    }
  }
}

nonisolated extension InstructorRating {
  var title: String {
    switch self {
      case .airplaneSingleEngine: String(localized: "Airplane Single-Engine")
      case .airplaneMultiEngine: String(localized: "Airplane Multi-Engine")
      case .glider: String(localized: "Glider")
      case .rotorcraftHelicopter: String(localized: "Rotorcraft Helicopter")
      case .rotorcraftGyroplane: String(localized: "Rotorcraft Gyroplane")
      case .poweredLift: String(localized: "Powered Lift")
      case .instrumentAirplane: String(localized: "Instrument Airplane")
      case .instrumentHelicopter: String(localized: "Instrument Helicopter")
      case .instrumentPoweredLift: String(localized: "Instrument Powered Lift")
      case .sport: String(localized: "Sport")
    }
  }
}
