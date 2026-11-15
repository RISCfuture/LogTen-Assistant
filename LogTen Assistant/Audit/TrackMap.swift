import Audit
import AuditWorkflow
import LogbookModel
import MapKit
import SwiftUI
import Tracks

/// The track to draw for a finding: positions and the events detected along them.
nonisolated struct FindingTrack: Hashable {
  private static let maximumSamples = 600

  /// The positions, in time order, thinned for drawing.
  let samples: [TrackSample]

  /// The events with known positions.
  let events: [TrackEvent]

  /// Creates a track from positions and events.
  init(samples: [TrackSample], events: [TrackEvent]) {
    self.samples = samples
    self.events = events
  }

  /**
   The track behind a finding: the segment it is about for unmatched activity, otherwise the
   evidence for its flight.

   - Returns: The track, or `nil` if the finding has no positions.
   */
  init?(for finding: Finding, in run: AuditRun) {
    var samples = [TrackSample]()
    var events = [TrackEvent]()
    if let segment = run.segment(for: finding) {
      samples = segment.track
      events = segment.events
    } else if let flightID = finding.recordIDs.first, let context = run.contexts[flightID] {
      let points = context.adsbPoints.isEmpty ? context.points : context.adsbPoints
      samples = points.filter { !$0.isPositionOutlier }.map(\.sample)
      events = context.events
    }
    events += run.followUps[finding.id]?.events ?? []
    guard samples.count > 1 else { return nil }
    let stride = max(1, samples.count / Self.maximumSamples)
    self.samples = Swift.stride(from: 0, to: samples.count, by: stride).map { samples[$0] }
    var seen = Set<TrackEvent>()
    self.events = events.filter { $0.latitudeDeg != nil && $0.longitudeDeg != nil }
      .filter { seen.insert($0).inserted }
  }
}

/// A map of a finding's track, with a pin at each detected event.
struct TrackMap: View {
  private static let height = 260.0

  let track: FindingTrack

  var body: some View {
    Map(interactionModes: [.pan, .zoom]) {
      MapPolyline(coordinates: track.samples.map(\.coordinate))
        .stroke(.tint, lineWidth: 3)
      ForEach(Array(track.events.enumerated()), id: \.offset) { _, event in
        if let latitude = event.latitudeDeg, let longitude = event.longitudeDeg {
          Marker(
            event.kind.title,
            systemImage: event.kind.systemImage,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
          )
        }
      }
    }
    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .including([.airport])))
    .frame(height: Self.height)
    .clipShape(.rect(cornerRadius: 8))
    .accessibilityLabel(
      String(
        localized:
          "Map of the recorded track, with \(track.events.count, format: .number) detected events"
      )
    )
    .accessibilityIdentifier("findingInspector.map")
  }
}

nonisolated extension TrackEvent.Kind {
  fileprivate var systemImage: String {
    switch self {
      case .takeoff: "airplane.departure"
      case .landing, .touchAndGo: "airplane.arrival"
      case .fullStop, .groundStop: "stop.circle"
      case .out, .in: "parkingsign"
      case .gap: "exclamationmark.triangle"
    }
  }
}

#Preview("In the Inspector") {
  InspectorColumnPreview {
    InspectorPage {
      InspectorSection("Track") { TrackMap(track: PreviewHelper.track) }
    }
  }
}
