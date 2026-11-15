# ``LogbookModel``

Value types for LogTen logbook records, settings and findings.

## Overview

Every type is a `Sendable`, `Codable` value, so the other modules pass records between actors and persist them freely. Durations are whole minutes and counts are unsigned integers, as LogTen stores them; ``FieldValue`` holds any attribute's value, and ``LogTenFieldKey`` names any attribute, including the custom fields a ``FieldMapping`` assigns to ``FieldRole``s.

A ``Finding`` is content-addressed: its ``FindingID`` is derived from its rule, records and evidence through ``CanonicalJSON``, so an unchanged audit produces the same identifiers and decisions carry forward. It offers alternative ``CorrectionOption``s, none on a flight its ``CorrectionRestriction`` protects, and its ``Severity`` is one of Flight Audit's tiers.

## Topics

### Logbooks

- ``Logbook``
- ``LogbookIdentity``
- ``LogbookGroup``
- ``SmartGroupCriterion``
- ``RecordID``
- ``RecordFingerprint``

### Records

- ``Flight``
- ``FlightEvents``
- ``FlightTimes``
- ``FlightCounts``
- ``FlightCrew``
- ``Aircraft``
- ``AircraftType``
- ``Person``
- ``Place``
- ``Approach``
- ``ApproachType``
- ``SimulatorType``
- ``SimulatorCategoryClass``

### Fields

- ``LogTenEntity``
- ``LogTenFieldKey``
- ``FieldValue``
- ``CustomFieldKind``
- ``CustomFieldSlot``
- ``CustomFieldValueKind``
- ``CustomFieldDefinition``
- ``FieldRole``
- ``FieldMapping``
- ``FieldMappingError``
- ``LogTenSlotValue``

### Settings

- ``LogbookSettings``
- ``PilotProfile``
- ``AircraftSettings``
- ``TrackDetectionOverrides``
- ``SimulatorCredit``
- ``ICAOAddress``
- ``RuleSettings``
- ``CustomRule``
- ``ConfirmedCurrencyEvent``
- ``AuditTolerances``

### Classification

- ``AircraftCategory``
- ``AircraftClass``
- ``EngineType``
- ``CategoryClassRating``
- ``CertificateLevel``
- ``InstrumentRating``
- ``InstructorRating``

### Findings

- ``Finding``
- ``FindingID``
- ``CorrectionOption``
- ``CorrectionOptionID``
- ``CorrectionRestriction``
- ``FieldChange``
- ``Severity``
- ``RuleID``
- ``JSONValue``
- ``CanonicalJSON``
