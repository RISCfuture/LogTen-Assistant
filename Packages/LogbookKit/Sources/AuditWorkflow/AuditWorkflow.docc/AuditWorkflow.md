# ``AuditWorkflow``

Runs, reviews and applies a whole Audit & Fix pass.

## Overview

``AuditRunner`` composes every audit over a snapshot from ``AuditInputs`` and returns an ``AuditRun`` whose findings fall into ``ReviewQueue``s, narrowed to recent flights by an ``AuditScope``. ``EvidenceLibrary`` keeps the FlySto evidence and sync cursor in the logbook's workspace. ``ReviewBook`` holds the user's decisions, saved as ``ReviewState`` and carried forward between runs, and ``FindingExporter`` writes findings out. ``ApplyPlan`` plans approved fixes against a fresh snapshot, and ``BatchDelivery`` delivers, journals, verifies and reverts batches.

## Topics

### Running

- ``AuditRunner``
- ``AuditInputs``
- ``AuditRun``
- ``AuditNote``
- ``ReviewQueue``
- ``AuditScope``
- ``AircraftCoverage``

### Evidence

- ``EvidenceLibrary``
- ``FlyStoSyncState``
- ``FlyStoSyncSummary``
- ``StaleDataSources``

### Reviewing

- ``ReviewBook``
- ``ReviewState``
- ``FindingExporter``

### Applying

- ``ApplyPlan``
- ``BatchDelivery``
- ``JournalDocument``
- ``BlockedChange``
- ``RevertError``
