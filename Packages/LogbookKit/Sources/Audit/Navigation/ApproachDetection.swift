public import Foundation
public import LogbookModel
public import References
public import Tracks

/// An approach the aircraft's track flew, identified by the published fixes it passed.
public struct ApproachEpisode: Hashable, Codable, Sendable {

  /// When the track passed the first matched fix.
  public var start: Date
  /// When the aircraft landed.
  public var end: Date
  /// The airport the aircraft landed at.
  public var airport: String
  /// The approach flown, if exactly one procedure fits.
  public var approach: PublishedApproach?
  /// The names of every procedure that fits equally well.
  public var candidates: [String]
  /// The kind of approach, if all fitting procedures agree.
  public var family: ApproachFamily?
  /// The runway, such as `28R`, if all fitting procedures agree.
  public var runway: String?
  /// The fixes the track passed, in order.
  public var fixesPassed: [String]
  /// How the episode was identified.
  public var basis: Basis

  /// The episode as the evidence of a finding records it.
  public var jsonValue: JSONValue {
    [
      "start": .string(start.formatted(.iso8601)),
      "end": .string(end.formatted(.iso8601)),
      "airport": .string(airport),
      "approach": approach.map { .string($0.name) } ?? .null,
      "candidates": .array(candidates.map(JSONValue.string)),
      "type": family.map { .string($0.rawValue) } ?? .null,
      "runway": runway.map(JSONValue.string) ?? .null,
      "fixes_passed": .array(fixesPassed.map(JSONValue.string)),
      "basis": .string(basis.rawValue)
    ]
  }

  /// How the episode was identified.
  public enum Basis: String, Codable, Sendable {
    /// The track passed the published fixes of an approach procedure in order.
    case publishedFixes = "published_fixes"
  }
}

/// Finds the approaches a track flew by matching it against published procedures.
///
/// Before each landing, the track must pass at least three fixes of one procedure to the
/// landing airport, in the order the procedure lists them, each within a short distance. When
/// several procedures fit equally well, such as an ILS and its localizer-only minimums, the
/// episode names what they agree on and lists the rest as candidates. A track that lacks the
/// resolution to pass near the fixes yields no episode, which is not evidence that no approach
/// was flown.
public struct ApproachDetector: Sendable {
  private static let minimumFixes = 3
  private static let nauticalMilesPerDegree = 60.0

  private let index: AirportIndex
  private let lookup: any ApproachLookup
  private let windowSeconds: TimeInterval
  private let fixToleranceNM: Double

  /**
   Creates a detector.

   - Parameters:
     - index: Airport positions, to find the airport of a landing.
     - lookup: The published approaches.
     - windowSeconds: How long before a landing to look for the approach.
     - fixToleranceNM: How near a fix the track must pass, in nautical miles.
   */
  public init(
    index: AirportIndex,
    lookup: any ApproachLookup,
    windowSeconds: TimeInterval = 900,
    fixToleranceNM: Double = 0.75
  ) {
    self.index = index
    self.lookup = lookup
    self.windowSeconds = windowSeconds
    self.fixToleranceNM = fixToleranceNM
  }

  /// The distance from a fix to the segment between two samples, in a local flat frame.
  private static func distanceNM(
    from fix: ApproachFix,
    toSegmentFrom a: TrackSample,
    to b: TrackSample
  )
    -> Double
  {
    let scale = nauticalMilesPerDegree * cos(fix.latitudeDeg * .pi / 180)
    func point(_ latitude: Double, _ longitude: Double) -> (x: Double, y: Double) {
      (
        (longitude - fix.longitudeDeg) * scale,
        (latitude - fix.latitudeDeg) * nauticalMilesPerDegree
      )
    }
    let start = point(a.latitudeDeg, a.longitudeDeg)
    let end = point(b.latitudeDeg, b.longitudeDeg)
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    let fraction =
      lengthSquared == 0 ? 0 : max(0, min(1, -(start.x * dx + start.y * dy) / lengthSquared))
    return
      ((start.x + fraction * dx) * (start.x + fraction * dx)
      + (start.y + fraction * dy) * (start.y + fraction * dy)).squareRoot()
  }

  /**
   The approaches flown before the landings of an entry.

   - Parameters:
     - context: The entry's evidence.
     - positions: The entry's usable positions, in time order.
   - Returns: One episode per landing at which an approach was identified.
   */
  public func episodes(in context: EvidenceContext, positions: [TrackSample]) async
    -> [ApproachEpisode]
  {
    var result = [ApproachEpisode]()
    let landings = context.events.filter { $0.kind == .landing && $0.confidence != .low }
    for landing in landings {
      guard let position = landing.validPosition,
        let airport = index.nearestAirport(
          latitudeDeg: position.latitudeDeg,
          longitudeDeg: position.longitudeDeg
        )
      else { continue }
      let approach = await approachCandidates(at: airport)
      let window = positions.filter {
        $0.time <= landing.time && landing.time.timeIntervalSince($0.time) <= windowSeconds
      }
      if let episode = episode(
        landing: landing,
        airport: airport,
        approaches: approach,
        window: window
      ) {
        result.append(episode)
      }
    }
    return result
  }

  private func approachCandidates(at airport: AirportReference) async -> [PublishedApproach] {
    for identifier in [airport.ICAOID, airport.locationID].compactMap(\.self) {
      let found = await lookup.approaches(at: identifier)
      if !found.isEmpty { return found }
    }
    return []
  }

  private func episode(
    landing: TrackEvent,
    airport: AirportReference,
    approaches: [PublishedApproach],
    window: [TrackSample]
  ) -> ApproachEpisode? {
    let matches = approaches.compactMap { approach in
      passedFixes(of: approach, along: window).map { (approach, $0) }
    }
    guard let best = matches.map(\.1.names.count).max() else { return nil }
    let fitting = matches.filter { $0.1.names.count == best }
    let family = Set(fitting.map(\.0.family)).onlyElement
    let runway = Set(fitting.compactMap(\.0.runway)).onlyElement
    return ApproachEpisode(
      start: fitting.map(\.1.start).min() ?? landing.time,
      end: landing.time,
      airport: airport.identifier,
      approach: fitting.count == 1 ? fitting[0].0 : nil,
      candidates: fitting.map(\.0.name).sorted(),
      family: family,
      runway: runway,
      fixesPassed: fitting[0].1.names,
      basis: .publishedFixes
    )
  }

  /// The fixes of an approach the track passed in order, if enough of them.
  private func passedFixes(of approach: PublishedApproach, along window: [TrackSample])
    -> (names: [String], start: Date)?
  {
    var names = [String]()
    var start: Date?
    var cursor = 0
    for fix in approach.fixes {
      guard let hit = firstPass(of: fix, along: window, from: cursor) else { continue }
      names.append(fix.name)
      start = start ?? window[hit].time
      cursor = hit
    }
    guard names.count >= min(Self.minimumFixes, approach.fixes.count), names.count >= 2,
      let start
    else { return nil }
    return (names, start)
  }

  /// The index of the first sample at or after `cursor` whose segment to the next sample passes
  /// the fix within the tolerance.
  private func firstPass(of fix: ApproachFix, along window: [TrackSample], from cursor: Int) -> Int?
  {
    guard window.count > cursor else { return nil }
    return (cursor..<window.count).first { position in
      let here = window[position]
      let next = window[min(position + 1, window.count - 1)]
      return Self.distanceNM(from: fix, toSegmentFrom: here, to: next) <= fixToleranceNM
    }
  }
}

extension Set {
  /// The only element, if there is exactly one.
  fileprivate var onlyElement: Element? { count == 1 ? first : nil }
}
