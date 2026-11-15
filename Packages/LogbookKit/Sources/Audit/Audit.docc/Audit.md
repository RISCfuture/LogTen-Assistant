# ``Audit``

Finds entries that disagree with themselves, with smart groups, or with external evidence.

## Overview

``ConsistencyAudit`` checks each entry's times, counts and references, and the completeness of its records, with one check per ``ConsistencyRule`` grouped by ``ConsistencyCategory``; ``SmartGroupAudit`` evaluates and checks smart groups. For evidence, ``EvidenceMatcher`` matches FlySto records and ``SegmentCorrelator`` correlates track segments to entries; ``EvidenceContextBuilder`` merges them per entry with FlySto preferred, and ``SourceComparison``, ``NightAudit``, ``GeographyAudit`` and ``NavigationAudit`` compare the merged evidence with the logbook.

## Topics

### Consistency

- ``ConsistencyAudit``
- ``ConsistencyAuditOptions``
- ``ConsistencyAuditResult``
- ``ConsistencyRule``
- ``ConsistencyCategory``
- ``FindingAnalysis``
- ``DateErrorCandidate``
- ``AuditReport``

### Smart groups

- ``SmartGroupAudit``
- ``SmartGroupAuditResult``
- ``SmartGroupEvaluation``
- ``SmartGroupRule``
- ``SmartGroupWindow``
- ``GroupMembershipResolving``

### Evidence

- ``AircraftIdentity``
- ``EvidenceMatcher``
- ``EvidenceMatch``
- ``SegmentCorrelator``
- ``SegmentCorrelation``
- ``SegmentMatch``
- ``CorrelationOverride``
- ``EvidenceContextBuilder``
- ``EvidenceContext``
- ``EvidencePoint``
- ``EvidenceError``
- ``InstructionPolicy``
- ``ExcludedFinding``

### Comparisons

- ``SourceComparison``
- ``SourceComparisonResult``
- ``SourceChoice``
- ``SourceObservation``
- ``ObservedField``
- ``AuditFollowUp``

### Night

- ``NightAudit``
- ``NightAuditOptions``
- ``NightAuditResult``
- ``NightTimeDiagnostics``
- ``TrackNightEstimate``
- ``EndpointNightComparison``

### Geography

- ``GeographyAudit``
- ``GeographyAuditOptions``
- ``GeographyAuditResult``
- ``CrossCountryDistances``

### Navigation

- ``NavigationAudit``
- ``NavigationAuditResult``
- ``ApproachDetector``
- ``ApproachEpisode``
- ``HoldDetector``
- ``HoldCandidate``
