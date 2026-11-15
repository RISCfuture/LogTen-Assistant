# ``Tracks``

Aircraft tracks from any source, with event detection and segmentation.

## Overview

A ``TrackSource`` provides ``Track``s of ``TrackSample``s. ``Track/detectEvents(settings:)`` finds takeoffs, landings, full stops and block events, and ``TrackSegmenter`` splits tracks into classified ``TrackSegment``s.

## Topics

### Tracks

- ``Track``
- ``TrackSample``
- ``TrackSource``
- ``SourceProvenance``
- ``EvidenceSource``

### Detection

- ``TrackDetectionSettings``
- ``TrackEvent``
- ``TrackSegmenter``
- ``TrackSegmentation``
- ``TrackSegment``
