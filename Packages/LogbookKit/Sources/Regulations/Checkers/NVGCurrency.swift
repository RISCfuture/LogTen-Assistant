import Foundation
import LogbookModel

/// The night-vision-goggle experience check shared by the solo and passenger rules.
///
/// To act as pilot in command using NVGs, a pilot needs three NVG takeoffs and three NVG
/// landings in the same category within the preceding calendar months, or an NVG proficiency
/// check in the same category in that time (14 CFR 61.57(f)).
struct NVGExperience: Sendable {
  private static let required: UInt = 3

  private let context: RegulationContext
  private let months: Int

  /// Creates a check.
  ///
  /// - Parameters:
  ///   - context: The logbook.
  ///   - months: The number of preceding calendar months that count.
  init(context: RegulationContext, months: Int) {
    self.context = context
    self.months = months
  }

  /// A flight's NVG takeoffs and landings are what make it subject to the rule.
  func isSubject(_ flight: Flight) -> Bool {
    if flight.isDualReceived || !flight.isPIC { return false }
    return flight.counts.nightVisionGoggleTakeoffs > 0
      && flight.counts.nightVisionGoggleLandings > 0
  }

  /// The recent NVG experience that falls short, or `nil` if the flight has enough experience or
  /// a proficiency check.
  func shortfall(before flight: Flight) -> Shortfall? {
    guard flight.aircraft != nil else { return nil }
    let recent = context.flights(
      within: .calendarMonths(months),
      of: flight,
      matching: context.sameCategory(for: flight, credit: .takeoffsAndLandings)
    )
    if recent.contains(where: { context.isMarked(.nightVisionGoggleProficiencyCheck, on: $0) }) {
      return nil
    }
    let takeoffs = recent.total(\.counts.nightVisionGoggleTakeoffs)
    let landings = recent.total(\.counts.nightVisionGoggleLandings)
    guard takeoffs < Self.required || landings < Self.required else { return nil }
    return Shortfall(takeoffs: takeoffs, landings: landings, flightIDs: recent.ids)
  }

  /// NVG experience that doesn't satisfy the rule.
  struct Shortfall: Sendable {
    /// The NVG takeoffs in the period.
    let takeoffs: UInt
    /// The NVG landings in the period.
    let landings: UInt
    /// The flights in the period.
    let flightIDs: [RecordID]
  }
}
