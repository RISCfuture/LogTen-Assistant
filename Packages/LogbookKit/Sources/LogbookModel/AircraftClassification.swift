/// A value LogTen stores as a numbered customization slot whose title the user can rename,
/// such as `flight_category1` titled “Airplane”.
///
/// Resolution tries the title first, so a renamed or reordered slot still resolves, and falls
/// back to LogTen's default assignment of slots.
public protocol LogTenSlotValue: CaseIterable, Sendable {
  /// The key prefix shared by every slot, such as `flight_category`.
  static var slotPrefix: String { get }

  /// The value LogTen assigns to each slot number by default.
  static var defaultSlots: [UInt: Self] { get }

  /// Normalized titles (lowercase, without spaces, hyphens or underscores) and their values.
  static var titles: [String: Self] { get }
}

extension LogTenSlotValue {
  /**
   Resolves a LogTen customization slot.

   - Parameters:
     - key: The slot's customization key, such as `flight_category1`.
     - title: The slot's title as the user sees it.
   - Returns: `nil` if neither the title nor the slot number is recognized.
   */
  public static func resolve(key: String?, title: String?) -> Self? {
    if let title, let value = titles[normalize(title)] { return value }
    guard let key, key.hasPrefix(slotPrefix), let number = UInt(key.dropFirst(slotPrefix.count))
    else { return nil }
    return defaultSlots[number]
  }

  private static func normalize(_ title: String) -> String {
    title.lowercased().filter { !" -_".contains($0) }
  }
}

/// FAA aircraft categories (14 CFR 1.1), plus LogTen's simulator and training-device categories.
public enum AircraftCategory: String, LogTenSlotValue, Codable {
  /// Airplane.
  case airplane
  /// Rotorcraft.
  case rotorcraft
  /// Powered lift.
  case poweredLift = "powered_lift"
  /// Glider.
  case glider
  /// Lighter-than-air.
  case lighterThanAir = "lighter_than_air"
  /// Full flight simulator.
  case simulator
  /// Flight training device.
  case trainingDevice = "training_device"
  /// Personal-computer aviation training device.
  case PC_ATD
  /// Powered parachute.
  case poweredParachute = "powered_parachute"
  /// Weight-shift control.
  case weightShiftControl = "weight_shift_control"
  /// Unmanned aircraft.
  case UAV
  /// Ultralight.
  case ultralight
  /// Any other category.
  case other

  public static let slotPrefix = "flight_category"

  public static let defaultSlots: [UInt: Self] = [
    1: .airplane, 2: .rotorcraft, 3: .poweredLift, 4: .glider, 5: .lighterThanAir,
    6: .simulator, 7: .trainingDevice, 8: .PC_ATD, 9: .poweredParachute,
    10: .weightShiftControl, 11: .UAV, 12: .other
  ]

  public static let titles: [String: Self] = [
    "airplane": .airplane, "rotorcraft": .rotorcraft, "poweredlift": .poweredLift,
    "glider": .glider, "lighterthanair": .lighterThanAir, "simulator": .simulator,
    "trainingdevice": .trainingDevice, "pcatd": .PC_ATD, "poweredparachute": .poweredParachute,
    "powerparachute": .poweredParachute, "weightshiftcontrol": .weightShiftControl,
    "uav": .UAV, "ultralight": .ultralight, "other": .other
  ]

  /// Whether the category is a simulator or training device rather than an aircraft.
  public var isSimulationDevice: Bool {
    switch self {
      case .simulator, .trainingDevice, .PC_ATD: true
      default: false
    }
  }
}

/// FAA aircraft classes (14 CFR 1.1), as LogTen records them.
public enum AircraftClass: String, LogTenSlotValue, Codable {
  /// Airplane multi-engine land.
  case multiEngineLand = "multi_engine_land"
  /// Airplane single-engine land.
  case singleEngineLand = "single_engine_land"
  /// Airplane multi-engine sea.
  case multiEngineSea = "multi_engine_sea"
  /// Airplane single-engine sea.
  case singleEngineSea = "single_engine_sea"
  /// Any other class.
  case other
  /// Rotorcraft gyroplane.
  case gyroplane
  /// Lighter-than-air airship.
  case airship
  /// Lighter-than-air free balloon.
  case freeBalloon = "free_balloon"
  /// Rotorcraft helicopter.
  case helicopter

  public static let slotPrefix = "flight_aircraftClass"

  public static let defaultSlots: [UInt: Self] = [
    1: .multiEngineLand, 2: .singleEngineLand, 3: .multiEngineSea, 4: .singleEngineSea,
    5: .other, 6: .gyroplane, 7: .airship, 8: .freeBalloon, 9: .helicopter
  ]

  public static let titles: [String: Self] = [
    "multiengineland": .multiEngineLand, "singleengineland": .singleEngineLand,
    "multienginesea": .multiEngineSea, "singleenginesea": .singleEngineSea, "other": .other,
    "gyroplane": .gyroplane, "airship": .airship, "freeballoon": .freeBalloon,
    "balloon": .freeBalloon, "helicopter": .helicopter
  ]
}

/// Aircraft engine types, as LogTen records them.
public enum EngineType: String, LogTenSlotValue, Codable {
  /// Turbojet.
  case jet
  /// Turbine, unspecified.
  case turbine
  /// Turboprop.
  case turboprop
  /// Reciprocating piston.
  case reciprocating
  /// Unpowered.
  case nonpowered
  /// Turboshaft.
  case turboshaft
  /// Turbofan.
  case turbofan
  /// Ramjet.
  case ramjet
  /// Two-stroke piston.
  case twoCycle = "two_cycle"
  /// Four-stroke piston.
  case fourCycle = "four_cycle"
  /// Any other engine.
  case other
  /// Electric motor.
  case electric

  public static let slotPrefix = "flight_engineType"

  public static let defaultSlots: [UInt: Self] = [
    1: .jet, 2: .turbine, 3: .turboprop, 4: .reciprocating, 5: .nonpowered, 6: .turboshaft,
    7: .turbofan, 8: .ramjet, 9: .twoCycle, 10: .fourCycle, 11: .other, 12: .electric
  ]

  public static let titles: [String: Self] = [
    "jet": .jet, "turbine": .turbine, "turboprop": .turboprop, "reciprocating": .reciprocating,
    "piston": .reciprocating, "nonpowered": .nonpowered, "turboshaft": .turboshaft,
    "turbofan": .turbofan, "ramjet": .ramjet, "2cycle": .twoCycle, "twocycle": .twoCycle,
    "4cycle": .fourCycle, "fourcycle": .fourCycle, "other": .other, "electric": .electric
  ]

  /// Whether the engine is a turbine of any kind, which makes the aircraft type-rated.
  public var isTurbine: Bool {
    switch self {
      case .jet, .turbine, .turboprop, .turboshaft, .turbofan, .ramjet: true
      default: false
    }
  }
}

/// Simulator and training-device types, as recorded in an aircraft type's custom field.
public enum SimulatorType: String, CaseIterable, Codable, Sendable {
  /// Basic aviation training device.
  case BATD
  /// Advanced aviation training device.
  case AATD
  /// Flight training device.
  case FTD
  /// Full flight simulator.
  case FFS
}

/// The category and class a simulator represents, as recorded in an aircraft type's custom field.
public enum SimulatorCategoryClass: String, CaseIterable, Codable, Sendable {
  /// Airplane single-engine land.
  case airplaneSingleEngineLand = "ASEL"
  /// Airplane single-engine sea.
  case airplaneSingleEngineSea = "ASES"
  /// Airplane multi-engine land.
  case airplaneMultiEngineLand = "AMEL"
  /// Airplane multi-engine sea.
  case airplaneMultiEngineSea = "AMES"
  /// Glider.
  case glider = "GL"

  /// The aircraft category the simulator represents.
  public var category: AircraftCategory {
    switch self {
      case .glider: .glider
      default: .airplane
    }
  }

  /// The aircraft class the simulator represents, or `nil` for a glider.
  public var aircraftClass: AircraftClass? {
    switch self {
      case .airplaneSingleEngineLand: .singleEngineLand
      case .airplaneSingleEngineSea: .singleEngineSea
      case .airplaneMultiEngineLand: .multiEngineLand
      case .airplaneMultiEngineSea: .multiEngineSea
      case .glider: nil
    }
  }
}

/// Instrument approach types, as LogTen records them.
public enum ApproachType: String, CaseIterable, Codable, Sendable {
  /// Ground-controlled approach.
  case GCA
  /// GBAS landing system.
  case GLS
  /// GPS/GNSS.
  case GPS_GNSS = "GPS/GNSS"
  /// Instrument guidance system.
  case IGS
  /// Instrument landing system.
  case ILS
  /// Joint precision approach and landing system.
  case JPALS
  /// Ground-based augmentation system.
  case GBAS
  /// Lateral navigation.
  case LNAV
  /// Lateral and vertical navigation.
  case LNAV_VNAV = "LNAV/VNAV"
  /// Localizer performance with vertical guidance.
  case LPV
  /// Microwave landing system.
  case MLS
  /// Precision approach radar.
  case PAR
  /// Wide-area augmentation system.
  case WAAS
  /// Airborne radar approach.
  case ARA
  /// Contact approach.
  case contact = "CONTACT"
  /// DME arc.
  case DME
  /// GPS, non-WAAS.
  case GPS
  /// Integrated approach navigation.
  case IAN
  /// Localizer-type directional aid.
  case LDA
  /// Localizer.
  case LOC
  /// Localizer back course.
  case LOC_BC = "LOC BC"
  /// Localizer with DME.
  case LOC_DME = "LOC/DME"
  /// Localizer performance.
  case LP
  /// Non-directional beacon.
  case NDB
  /// Area navigation.
  case RNAV
  /// Required navigation performance.
  case RNP
  /// Simplified directional facility.
  case SDF
  /// Surveillance radar approach.
  case SRA
  /// TACAN.
  case TACAN
  /// Visual approach.
  case visual = "VISUAL"
  /// VOR.
  case VOR
  /// VOR with DME.
  case VOR_DME = "VOR/DME"

  /// Whether the approach is an instrument approach for 14 CFR 61.57(c) currency; contact and
  /// visual approaches are not.
  public var isInstrumentApproach: Bool { self != .contact && self != .visual }
}
