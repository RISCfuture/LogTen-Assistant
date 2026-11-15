public import Foundation
import MeasurementKit

/// The durations logged on a flight, in whole minutes as LogTen stores them.
public struct FlightTimes: Hashable, Codable, Sendable {
  /// Total time.
  public var total: UInt
  /// Pilot-in-command time.
  public var PIC: UInt
  /// Second-in-command time.
  public var SIC: UInt
  /// Solo time.
  public var solo: UInt
  /// Night time.
  public var night: UInt
  /// Cross-country time.
  public var crossCountry: UInt
  /// Dual instruction given.
  public var dualGiven: UInt
  /// Dual instruction received.
  public var dualReceived: UInt
  /// Actual instrument time.
  public var actualInstrument: UInt
  /// Simulated instrument time.
  public var simulatedInstrument: UInt
  /// Simulator or training-device time.
  public var simulator: UInt
  /// Ground training time.
  public var ground: UInt
  /// Night-vision-goggle time.
  public var nightVisionGoggle: UInt

  /// Creates a set of flight times, in minutes.
  public init(
    total: UInt = 0,
    PIC: UInt = 0,
    SIC: UInt = 0,
    solo: UInt = 0,
    night: UInt = 0,
    crossCountry: UInt = 0,
    dualGiven: UInt = 0,
    dualReceived: UInt = 0,
    actualInstrument: UInt = 0,
    simulatedInstrument: UInt = 0,
    simulator: UInt = 0,
    ground: UInt = 0,
    nightVisionGoggle: UInt = 0
  ) {
    self.total = total
    self.PIC = PIC
    self.SIC = SIC
    self.solo = solo
    self.night = night
    self.crossCountry = crossCountry
    self.dualGiven = dualGiven
    self.dualReceived = dualReceived
    self.actualInstrument = actualInstrument
    self.simulatedInstrument = simulatedInstrument
    self.simulator = simulator
    self.ground = ground
    self.nightVisionGoggle = nightVisionGoggle
  }

  /// Returns one of the times as a duration, for display.
  ///
  /// - Parameter time: The time to measure, such as `\.night`.
  public func duration(_ time: KeyPath<Self, UInt>) -> Measurement<UnitDuration> {
    Measurement(value: Double(self[keyPath: time]), unit: .minutes)
  }
}

/// The takeoffs, landings and procedures logged on a flight.
public struct FlightCounts: Hashable, Codable, Sendable {
  /// Day takeoffs.
  public var dayTakeoffs: UInt
  /// Night takeoffs.
  public var nightTakeoffs: UInt
  /// Day landings.
  public var dayLandings: UInt
  /// Night landings.
  public var nightLandings: UInt
  /// Full-stop landings, day or night.
  public var fullStops: UInt
  /// Night-vision-goggle takeoffs.
  public var nightVisionGoggleTakeoffs: UInt
  /// Night-vision-goggle landings.
  public var nightVisionGoggleLandings: UInt
  /// Holding procedures.
  public var holds: UInt

  /// Day and night takeoffs.
  public var takeoffs: UInt { dayTakeoffs + nightTakeoffs }

  /// Day and night landings.
  public var landings: UInt { dayLandings + nightLandings }

  /// Creates a set of counts.
  public init(
    dayTakeoffs: UInt = 0,
    nightTakeoffs: UInt = 0,
    dayLandings: UInt = 0,
    nightLandings: UInt = 0,
    fullStops: UInt = 0,
    nightVisionGoggleTakeoffs: UInt = 0,
    nightVisionGoggleLandings: UInt = 0,
    holds: UInt = 0
  ) {
    self.dayTakeoffs = dayTakeoffs
    self.nightTakeoffs = nightTakeoffs
    self.dayLandings = dayLandings
    self.nightLandings = nightLandings
    self.fullStops = fullStops
    self.nightVisionGoggleTakeoffs = nightVisionGoggleTakeoffs
    self.nightVisionGoggleLandings = nightVisionGoggleLandings
    self.holds = holds
  }
}

/// The people in each crew position on a flight.
public struct FlightCrew: Hashable, Codable, Sendable {
  /// Pilot in command.
  public var PIC: Person?
  /// Second in command.
  public var SIC: Person?
  /// Flight instructor.
  public var instructor: Person?
  /// Student.
  public var student: Person?
  /// Flight engineer.
  public var flightEngineer: Person?
  /// Commander.
  public var commander: Person?
  /// Purser.
  public var purser: Person?
  /// Observers, in position order.
  public var observers: [Person]
  /// Relief crew, in position order.
  public var relief: [Person]
  /// Flight attendants, in position order.
  public var flightAttendants: [Person]
  /// People in the custom crew roles, keyed by slot number (`flight_selectedCrewCustom1`–`10`).
  public var custom: [UInt: Person]

  /// Everyone in a crew position, without duplicates.
  public var everyone: [Person] {
    var seen = Set<RecordID>()
    let all =
      [PIC, SIC, instructor, student, flightEngineer, commander, purser].compactMap(\.self)
      + observers + relief + flightAttendants + custom.keys.sorted().compactMap { custom[$0] }
    return all.filter { seen.insert($0.id).inserted }
  }

  /// Creates a crew.
  public init(
    PIC: Person? = nil,
    SIC: Person? = nil,
    instructor: Person? = nil,
    student: Person? = nil,
    flightEngineer: Person? = nil,
    commander: Person? = nil,
    purser: Person? = nil,
    observers: [Person] = [],
    relief: [Person] = [],
    flightAttendants: [Person] = [],
    custom: [UInt: Person] = [:]
  ) {
    self.PIC = PIC
    self.SIC = SIC
    self.instructor = instructor
    self.student = student
    self.flightEngineer = flightEngineer
    self.commander = commander
    self.purser = purser
    self.observers = observers
    self.relief = relief
    self.flightAttendants = flightAttendants
    self.custom = custom
  }
}

/// The out, off, on and in times of a flight, plus duty times, all in UTC.
public struct FlightEvents: Hashable, Codable, Sendable {
  /// Block out (actual departure).
  public var out: Date?
  /// Wheels up (takeoff).
  public var off: Date?
  /// Wheels down (landing).
  public var on: Date?
  /// Block in (actual arrival).
  public var `in`: Date?
  /// Start of duty.
  public var onDuty: Date?
  /// End of duty.
  public var offDuty: Date?

  /// The time from block out to block in, if both are logged.
  public var blockTime: Measurement<UnitDuration>? {
    guard let out, let `in` else { return nil }
    return `in`.elapsed(since: out)
  }

  /// The time from takeoff to landing, if both are logged.
  public var airborneTime: Measurement<UnitDuration>? {
    guard let off, let on else { return nil }
    return on.elapsed(since: off)
  }

  /// Creates a set of flight events.
  public init(
    out: Date? = nil,
    off: Date? = nil,
    on: Date? = nil,
    in: Date? = nil,
    onDuty: Date? = nil,
    offDuty: Date? = nil
  ) {
    self.out = out
    self.off = off
    self.on = on
    self.in = `in`
    self.onDuty = onDuty
    self.offDuty = offDuty
  }
}
