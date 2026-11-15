public import Foundation
import FlightSources
public import LogbookModel
public import References
public import Tracks

extension RuleID {
  /// Logged night time falls outside what the aircraft's track allows.
  public static let telemetryNightTime: Self = "telemetry_night_time"
  /// Logged day or night takeoffs or landings differ from the aircraft's events.
  public static let telemetryNightEvent: Self = "telemetry_night_event"
  /// Logged night full stops differ from the aircraft's events.
  public static let telemetryNightFullStops: Self = "telemetry_night_full_stops"
}

/// Settings for ``NightAudit``.
public struct NightAuditOptions: Hashable, Codable, Sendable {
  /// The longest interval between positions that is still treated as continuous coverage, in
  /// seconds.
  public var gapSeconds: Double

  /// Whether night takeoffs are counted by the one-hour-after-sunset window that governs night
  /// currency rather than by civil twilight.
  public var nightTakeoffsUseCurrencyWindow: Bool

  /// Creates options.
  public init(gapSeconds: Double = 120, nightTakeoffsUseCurrencyWindow: Bool = false) {
    self.gapSeconds = gapSeconds
    self.nightTakeoffsUseCurrencyWindow = nightTakeoffsUseCurrencyWindow
  }
}

/// How the logged night time compares with the aircraft's track and with a simple model of
/// LogTen's calculation.
public struct NightTimeDiagnostics: Hashable, Codable, Sendable {
  /// The estimate from the aircraft's positions.
  public var track: TrackNightEstimate
  /// The endpoint model, if both airports' positions are known.
  public var endpoint: EndpointNightComparison?
  /// The interval the estimates cover.
  public var interval: DateInterval
  /// Whether the interval is the logged out and in times rather than the source's.
  public var usesLoggedBlockTimes: Bool
  /// Which explanation fits.
  public var explanation: String
}

/// The findings of a night audit and what helps a reviewer decide them.
public struct NightAuditResult: Hashable, Sendable {
  /// The findings.
  public var findings: [Finding]
  /// The follow-up of each finding.
  public var followUps: [FindingID: AuditFollowUp]
  /// The track analysis behind each `RuleID.telemetryNightTime` finding.
  public var diagnostics: [FindingID: NightTimeDiagnostics]
}

/**
 Reviews logged night time, night takeoffs and landings, and night full stops against the
 aircraft's track, a port of cleanup-logten's `night_audit`.

 Night time is judged against bounds from the sampled positions, so a gap in coverage widens the
 bounds instead of being guessed. Event counts are judged only when the track's events are the
 complete record of the flight: its segments are whole, the positions leave no gap, and
 FlySto's count agrees with the number of events. Entries flown as instruction are not compared,
 since the aircraft's activity doesn't say who flew. Nothing here proposes a change.
 */
public struct NightAudit: Sendable {
  private static let civilReference =
    "https://www.ecfr.gov/current/title-14/chapter-I/subchapter-A/part-1/section-1.1"
  private static let currencyReference =
    "https://www.ecfr.gov/current/title-14/chapter-I/subchapter-D/part-61/subpart-A/section-61.57"
  private static let fullStopSearchSeconds = 1_800.0
  private static let fullStopRadiusNM = 0.5
  private static let endpointAgreementMinutes = 2.0

  private let mapping: FieldMapping
  private let tolerances: AuditTolerances
  private let options: NightAuditOptions
  private let index: AirportIndex?

  /**
   Creates an audit.

   - Parameters:
     - mapping: Which custom fields hold night takeoffs and night full stops.
     - tolerances: How far logged night time may stray outside the bounds.
     - options: Coverage and window settings.
     - index: Airport positions, for the endpoint model.
   */
  public init(
    mapping: FieldMapping,
    tolerances: AuditTolerances = .init(),
    options: NightAuditOptions = .init(),
    index: AirportIndex? = nil
  ) {
    self.mapping = mapping
    self.tolerances = tolerances
    self.options = options
    self.index = index
  }

  private static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }

  /**
   Audits the entries that have external evidence.

   - Parameters:
     - flights: The logbook entries.
     - contexts: The evidence for each entry.
   */
  public func run(on flights: [Flight], contexts: [RecordID: EvidenceContext]) -> NightAuditResult {
    var result = NightAuditResult(findings: [], followUps: [:], diagnostics: [:])
    for flight in flights where !flight.isSimulatorEntry {
      guard let context = contexts[flight.id], let interval = interval(of: context) else {
        continue
      }
      let samples = context.usablePositions
      let loggedInterval = loggedInterval(of: flight) ?? interval
      addTimeFinding(flight, context, samples, loggedInterval, to: &result)
      for finding in eventFindings(flight, context, samples, interval) {
        result.findings.append(finding.finding)
        result.followUps[finding.finding.id] = finding.followUp
      }
    }
    return result
  }

  private func interval(of context: EvidenceContext) -> DateInterval? {
    guard let start = context.start, let end = context.end, end > start else { return nil }
    return DateInterval(start: start, end: end)
  }

  private func loggedInterval(of flight: Flight) -> DateInterval? {
    guard let out = flight.events.out, let `in` = flight.events.in, `in` > out else { return nil }
    return DateInterval(start: out, end: `in`)
  }

  // MARK: Night time

  private func addTimeFinding(
    _ flight: Flight,
    _ context: EvidenceContext,
    _ samples: [TrackSample],
    _ interval: DateInterval,
    to result: inout NightAuditResult
  ) {
    guard
      let track = TrackNightEstimate(
        samples: samples,
        from: interval.start,
        to: interval.end,
        gapSeconds: options.gapSeconds
      )
    else { return }
    let logged = Double(flight.times.night)
    let tolerance = Double(tolerances.timeToleranceMinutes)
    let isPartial = Double(flight.times.total) < track.intervalMinutes
    let isTooLow = logged < track.minimumMinutes - tolerance && !isPartial && !context.isInstruction
    guard isTooLow || logged > track.maximumMinutes + tolerance else { return }

    let observation: [String: JSONValue] = [
      "min": .double(Self.rounded(track.minimumMinutes)),
      "max": .double(Self.rounded(track.maximumMinutes)),
      "interval_minutes": .double(Self.rounded(track.intervalMinutes)),
      "classified_minutes": .double(Self.rounded(track.classifiedMinutes)),
      "unknown_minutes": .double(Self.rounded(track.maximumMinutes - track.minimumMinutes)),
      "partial_credit": .bool(isPartial),
      "track_estimate": track.jsonValue
    ]
    let finding = candidate(
      flight,
      context,
      rule: .telemetryNightTime,
      field: .flightNight,
      logged: Int(logged),
      observation: observation,
      events: context.events,
      isCurrencyWindow: false
    )
    result.findings.append(finding.finding)
    result.followUps[finding.finding.id] = finding.followUp
    let endpoint = endpointComparison(flight, interval)
    result.diagnostics[finding.finding.id] = NightTimeDiagnostics(
      track: track,
      endpoint: endpoint,
      interval: interval,
      usesLoggedBlockTimes: loggedInterval(of: flight) != nil,
      explanation: explanation(logged: logged, track: track, endpoint: endpoint)
    )
  }

  private func explanation(
    logged: Double,
    track: TrackNightEstimate,
    endpoint: EndpointNightComparison?
  ) -> String {
    if let endpoint,
      endpoint.samplingMinimumMinutes - Self.endpointAgreementMinutes <= logged,
      logged <= endpoint.samplingMaximumMinutes + Self.endpointAgreementMinutes
    {
      return String(
        localized:
          "The six-minute endpoint model can explain the logged value. The actual route and speed history produce a different night estimate. Review whether to use the more detailed aircraft-position calculation.",
        bundle: .module
      )
    }
    if logged < track.minimumMinutes {
      return String(
        localized:
          "Even the observed-position lower bound exceeds the logged night credit. Missing positions remain unknown; this is not just a six-minute rounding difference.",
        bundle: .module
      )
    }
    return String(
      localized:
        "The logged night credit exceeds the actual-position upper bound. Compare the endpoint model, interval and any partial personal credit before editing.",
      bundle: .module
    )
  }

  private func endpointComparison(_ flight: Flight, _ interval: DateInterval)
    -> EndpointNightComparison?
  {
    guard let origin = position(of: flight.from), let destination = position(of: flight.to)
    else { return nil }
    return EndpointNightComparison(
      from: interval.start,
      to: interval.end,
      origin: origin,
      destination: destination
    )
  }

  private func position(of place: Place?) -> (latitudeDeg: Double, longitudeDeg: Double)? {
    guard let place else { return nil }
    if let airport = index?.airport(matching: place.preferredIdentifier)
      ?? index?.airport(matching: place.identifier)
    {
      return (airport.latitudeDeg, airport.longitudeDeg)
    }
    guard let latitude = place.latitudeDeg, let longitude = place.longitudeDeg else { return nil }
    return (latitude, longitude)
  }

  // MARK: Events

  private func eventFindings(
    _ flight: Flight,
    _ context: EvidenceContext,
    _ samples: [TrackSample],
    _ interval: DateInterval
  ) -> [(finding: Finding, followUp: AuditFollowUp)] {
    guard !context.isInstruction, hasCompleteEvents(context, samples, interval) else { return [] }
    var result = [(finding: Finding, followUp: AuditFollowUp)]()
    if let takeoffs = classifiedEvents(.takeoff, in: context, interval) {
      let isCurrency = options.nightTakeoffsUseCurrencyWindow
      result += countFindings(
        flight,
        context,
        events: takeoffs,
        dayKey: .flightDayTakeoffs,
        nightKey: mapping[.nightTakeoffs],
        isCurrencyWindow: isCurrency
      )
    }
    if let landings = classifiedEvents(.landing, in: context, interval) {
      result += countFindings(
        flight,
        context,
        events: landings,
        dayKey: .flightDayLandings,
        nightKey: .flightNightLandings,
        isCurrencyWindow: false
      )
      result += fullStopFindings(flight, context, landings: landings, interval)
    }
    return result
  }

  /// Whether the events are the whole record of the flight: whole segments, a position at
  /// least every gap across the interval, and no gap event.
  private func hasCompleteEvents(
    _ context: EvidenceContext,
    _ samples: [TrackSample],
    _ interval: DateInterval
  ) -> Bool {
    guard !context.segments.isEmpty,
      !context.segments.contains(where: { $0.isIncompleteAtStart || $0.isIncompleteAtEnd }),
      let first = samples.first, let last = samples.last,
      first.time <= interval.start, last.time >= interval.end
    else { return false }
    let covering = zip(samples, samples.dropFirst()).filter {
      $1.time > interval.start && $0.time < interval.end
    }
    guard covering.allSatisfy({ $1.time.timeIntervalSince($0.time) <= options.gapSeconds }) else {
      return false
    }
    return !context.events.contains { $0.kind == .gap && interval.contains($0.time) }
  }

  private func classifiedEvents(
    _ kind: TrackEvent.Kind,
    in context: EvidenceContext,
    _ interval: DateInterval
  ) -> [ClassifiedEvent]? {
    guard let countKind = FlyStoCountKind(rawValue: kind.rawValue),
      context.countSources[countKind] == .flySto,
      let preferred = context.counts[countKind]
    else { return nil }
    let events = context.events.filter { $0.kind == kind && interval.contains($0.time) }
      .sorted { $0.time < $1.time }
    guard preferred == UInt(events.count),
      events.allSatisfy({ $0.validPosition != nil && $0.confidence != .low })
    else { return nil }
    return events.map { event in
      let position = event.validPosition!
      return ClassifiedEvent(
        event: event,
        night: NightWindow.classify(
          at: event.time,
          latitudeDeg: position.latitudeDeg,
          longitudeDeg: position.longitudeDeg
        )
      )
    }
  }

  private func countFindings(
    _ flight: Flight,
    _ context: EvidenceContext,
    events: [ClassifiedEvent],
    dayKey: LogTenFieldKey,
    nightKey: LogTenFieldKey?,
    isCurrencyWindow: Bool
  ) -> [(finding: Finding, followUp: AuditFollowUp)] {
    let verdicts = events.map {
      isCurrencyWindow ? $0.night.isCurrencyNight : $0.night.isCivilNight
    }
    guard !verdicts.contains(nil) else { return [] }
    return [(dayKey, false), (nightKey, true)].compactMap { key, isNight in
      guard let key else { return nil }
      let observed = verdicts.filter { $0 == isNight }.count
      return countCandidate(
        flight,
        context,
        key: key,
        observed: observed,
        events: events.map(\.event),
        isCurrencyWindow: isCurrencyWindow,
        isFullStop: false
      )
    }
  }

  private func fullStopFindings(
    _ flight: Flight,
    _ context: EvidenceContext,
    landings: [ClassifiedEvent],
    _ interval: DateInterval
  ) -> [(finding: Finding, followUp: AuditFollowUp)] {
    guard let key = mapping[.nightFullStops],
      let stops = fullStopEvents(for: landings, in: context, interval),
      !stops.contains(where: { $0.night.isCurrencyNight == nil })
    else { return [] }
    let observed = stops.filter { $0.isFullStop && $0.night.isCurrencyNight == true }.count
    return countCandidate(
      flight,
      context,
      key: key,
      observed: observed,
      events: stops.map(\.event),
      isCurrencyWindow: true,
      isFullStop: true
    ).map { [$0] } ?? []
  }

  /// Pairs each landing with the one full-stop or touch-and-go event that follows it on the
  /// runway; `nil` if any landing has no such pair or several.
  private func fullStopEvents(
    for landings: [ClassifiedEvent],
    in context: EvidenceContext,
    _ interval: DateInterval
  ) -> [ClassifiedEvent]? {
    let events = context.events.filter { interval.contains($0.time) }
    var used = Set<Int>()
    var result = [ClassifiedEvent]()
    for landing in landings {
      guard let landingPosition = landing.event.validPosition else { return nil }
      let candidates = events.indices.filter { index in
        let event = events[index]
        guard !used.contains(index), event.kind == .fullStop || event.kind == .touchAndGo,
          let position = event.validPosition, event.confidence != .low
        else { return false }
        let delay = event.time.timeIntervalSince(landing.event.time)
        return delay >= 0 && delay <= Self.fullStopSearchSeconds
          && GreatCircle.distanceNM(
            position.latitudeDeg,
            position.longitudeDeg,
            landingPosition.latitudeDeg,
            landingPosition.longitudeDeg
          ) <= Self.fullStopRadiusNM
          && !events.contains {
            [.takeoff, .landing, .gap].contains($0.kind) && $0.time > landing.event.time
              && $0.time <= event.time
          }
      }
      guard candidates.count == 1, let index = candidates.first else { return nil }
      used.insert(index)
      var classified = landing
      classified.isFullStop = events[index].kind == .fullStop
      result.append(classified)
    }
    return result
  }

  private func countCandidate(
    _ flight: Flight,
    _ context: EvidenceContext,
    key: LogTenFieldKey,
    observed: Int,
    events: [TrackEvent],
    isCurrencyWindow: Bool,
    isFullStop: Bool
  ) -> (finding: Finding, followUp: AuditFollowUp)? {
    let logged = Int(flight[field: key].unsignedInteger ?? 0)
    guard logged != observed else { return nil }
    return candidate(
      flight,
      context,
      rule: isFullStop ? .telemetryNightFullStops : .telemetryNightEvent,
      field: key,
      logged: logged,
      observation: ["observed": .integer(observed)],
      events: events,
      isCurrencyWindow: isCurrencyWindow
    )
  }

  // MARK: Findings

  private func candidate(
    _ flight: Flight,
    _ context: EvidenceContext,
    rule: RuleID,
    field: LogTenFieldKey,
    logged: Int,
    observation: [String: JSONValue],
    events: [TrackEvent],
    isCurrencyWindow: Bool
  ) -> (finding: Finding, followUp: AuditFollowUp) {
    var evidence = context.provenanceEvidence
    evidence["field"] = .string(field.attributeName.lowercased())
    evidence["logged"] = .integer(logged)
    evidence["window"] = .string(
      isCurrencyWindow ? "sunset + 1 hour to sunrise - 1 hour" : "civil twilight"
    )
    evidence.merge(observation) { _, new in new }
    let finding = Finding(
      rule: rule,
      recordIDs: [flight.id],
      message: String(
        localized:
          "Logged night credit differs from the bounded aircraft observations; review pilot attribution and field semantics.",
        bundle: .module
      ),
      evidence: .object(evidence),
      citation: isCurrencyWindow ? Self.currencyReference : Self.civilReference
    )
    return (
      finding,
      AuditFollowUp(
        summary: String(
          localized:
            "Review solar-window evidence and pilot attribution before considering a correction.",
          bundle: .module
        ),
        notes: notes(flight, context),
        events: events,
        sources: context.urls
      )
    )
  }

  private func notes(_ flight: Flight, _ context: EvidenceContext) -> [String] {
    var notes = [
      String(
        localized:
          "Civil-twilight bounds use observed positions and geometric solar-center elevation strictly below −6 degrees, without atmospheric refraction; gaps, missing positions and twilight transitions remain unknown.",
        bundle: .module
      ),
      String(
        localized:
          "Between nearby samples the position follows the sampled path. Bounds include a solar/movement margin; they are review evidence, not an Air Almanac certification.",
        bundle: .module
      ),
      String(
        localized:
          "Aircraft activity does not establish who flew, personal credit or passenger currency. Confirm attribution before changing any field.",
        bundle: .module
      ),
      String(
        localized:
          "Day/night counts use civil twilight; the mapped night full-stop field uses one hour after sunset to one hour before sunrise at touchdown.",
        bundle: .module
      ),
      String(
        localized:
          "Event comparisons require continuous observations, complete segments and agreement with the preferred source’s totals. An unclassified landing is not treated as a non-full-stop landing.",
        bundle: .module
      )
    ]
    if context.isInstruction {
      notes.append(
        String(
          localized:
            "Instructor/student flight: missing personal night credit and event counts are excluded; upper-bound violations remain reviewable.",
          bundle: .module
        )
      )
    }
    if flight.isLocked || flight.isSigned {
      notes.append(
        String(
          localized: "Signed or locked entry: leave unchanged and preserve signatures.",
          bundle: .module
        )
      )
    }
    return notes
  }

  private struct ClassifiedEvent {
    var event: TrackEvent
    var night: NightClassification
    var isFullStop = false
  }
}
