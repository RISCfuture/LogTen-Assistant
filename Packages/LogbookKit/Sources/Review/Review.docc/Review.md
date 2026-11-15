# ``Review``

Review decisions about findings, carried from one audit run to the next.

## Overview

A ``ReviewRecord`` holds a ``ReviewDecision`` about one finding and, for a correction, the option chosen. ``DecisionCarryForward`` keeps a decision for the next ``ReviewedAudit`` only while its records and evidence are unchanged, and ``ReviewExport`` exchanges decisions tied to a run's ``AuditIdentity``.

## Topics

### Decisions

- ``ReviewDecision``
- ``ReviewReason``
- ``ReviewRecord``

### Runs

- ``ReviewedAudit``
- ``AuditIdentity``
- ``DecisionCarryForward``
- ``CarryForwardResult``
- ``CarryForwardEntry``
- ``RetiredFinding``

### Exchange

- ``ReviewExport``
- ``ReviewExportError``
