public import Foundation

extension Track {
  /**
   Finds takeoffs, landings, full stops, touch-and-goes and block movement in the track.

   A change between ground and air becomes an event only after it holds for
   ``TrackDetectionSettings/confirmSeconds``, and an event is stamped with the first sample of
   the change. A sample reported on the ground counts as ground at any speed; a sample without
   a ground speed and without a ground report is ignored.

   - Parameter settings: The thresholds to detect with.
   - Returns: The events, in time order.
   */
  public func detectEvents(settings: TrackDetectionSettings = .init()) -> [TrackEvent] {
    var detector = EventDetector(settings: settings)
    for sample in samples { detector.process(sample) }
    return detector.events.sorted { ($0.time, $0.kind.rawValue) < ($1.time, $1.kind.rawValue) }
  }
}

/// A port of cleanup-logten's `telemetry.detect_events` state machine, without the engine and
/// approach-annunciation logic that needs onboard data.
struct EventDetector {
  private(set) var events = [TrackEvent]()
  private let settings: TrackDetectionSettings

  private var phase: Phase?
  private var candidate: Phase?
  private var candidateStart: TrackSample?
  private var previousTime: Date?
  private var isMoving = false

  private var motionStart: TrackSample?
  private var stationaryStart: TrackSample?
  private var lastLanding: TrackSample?
  private var hadGround = false

  private var fullStopStart: TrackSample?
  private var seenLanding = false

  init(settings: TrackDetectionSettings) {
    self.settings = settings
  }

  mutating func process(_ sample: TrackSample) {
    if startsAfterGap(sample) {
      events.append(TrackEvent(.gap, at: sample, confidence: .low))
      resetState()
    }
    previousTime = sample.time
    let isOnGround = sample.isOnGround == true
    guard let speed = sample.groundSpeedKts ?? (isOnGround ? 0 : nil) else { return }
    trackPhase(sample, speed: speed, isOnGround: isOnGround)
    trackFullStop(sample)
    trackMovement(sample, speed: speed)
  }

  private func startsAfterGap(_ sample: TrackSample) -> Bool {
    guard let previousTime else { return false }
    return sample.time.timeIntervalSince(previousTime) > settings.gapSeconds
      || sample.time < previousTime
  }

  private mutating func resetState() {
    phase = nil
    candidate = nil
    isMoving = false
    stationaryStart = nil
    motionStart = nil
    lastLanding = nil
    hadGround = false
    fullStopStart = nil
    seenLanding = false
  }

  private func observedPhase(speed: Double, isOnGround: Bool) -> Phase? {
    if speed >= settings.airborneKts && !isOnGround { return .air }
    if speed <= settings.groundKts || isOnGround { return .ground }
    return nil
  }

  private mutating func trackPhase(_ sample: TrackSample, speed: Double, isOnGround: Bool) {
    guard let observed = observedPhase(speed: speed, isOnGround: isOnGround) else { return }
    guard let current = phase else {
      phase = observed
      hadGround = observed == .ground
      return
    }
    guard observed != current else {
      candidate = nil
      return
    }
    guard candidate == observed, let candidateStart else {
      candidate = observed
      candidateStart = sample
      return
    }
    if sample.time.timeIntervalSince(candidateStart.time) >= settings.confirmSeconds {
      confirm(observed, firstSample: candidateStart)
    }
  }

  private mutating func confirm(_ observed: Phase, firstSample: TrackSample) {
    switch observed {
      case .air where hadGround:
        events.append(TrackEvent(.takeoff, at: firstSample))
        if let lastLanding, !hasFullStop(since: lastLanding.time) {
          events.append(TrackEvent(.touchAndGo, at: lastLanding))
        }
        lastLanding = nil
      case .ground:
        events.append(TrackEvent(.landing, at: firstSample))
        lastLanding = firstSample
        hadGround = true
        seenLanding = true
      case .air:
        break
    }
    phase = observed
    candidate = nil
  }

  private func hasFullStop(since time: Date) -> Bool {
    events.contains { $0.kind == .fullStop && $0.time >= time }
  }

  private mutating func trackFullStop(_ sample: TrackSample) {
    guard let groundSpeed = sample.groundSpeedKts, groundSpeed <= settings.fullStopKts,
      phase == .ground
    else {
      fullStopStart = nil
      return
    }
    let start = fullStopStart ?? sample
    fullStopStart = start
    if let landing = lastLanding,
      sample.time.timeIntervalSince(start.time) >= settings.fullStopSeconds
    {
      events.append(TrackEvent(.fullStop, at: landing))
      lastLanding = nil
    }
  }

  private mutating func trackMovement(_ sample: TrackSample, speed: Double) {
    if speed > settings.movementKts {
      stationaryStart = nil
      guard !isMoving, phase == .ground else { return }
      guard let start = motionStart else {
        motionStart = sample
        return
      }
      if sample.time.timeIntervalSince(start.time) >= settings.confirmSeconds {
        events.append(TrackEvent(.out, at: start))
        isMoving = true
      }
    } else {
      motionStart = nil
      let start = stationaryStart ?? sample
      stationaryStart = start
      if isMoving, sample.time.timeIntervalSince(start.time) >= settings.stopSeconds {
        events.append(TrackEvent(seenLanding ? .in : .groundStop, at: start))
        isMoving = false
      }
    }
  }

  private enum Phase { case air, ground }
}
