# ``Corrections``

Applies approved fixes through LogTen's import, safely.

## Overview

A ``CorrectionProposal`` of approved findings, each an ``ApprovedCorrection`` with the option the reviewer chose, is checked by ``Preflight`` against a fresh snapshot; what can't be imported goes to a ``ManualChecklist``. The rest is split into ``CorrectionBatch``es, pilot batch first, packaged as ``ImportPackage``s and delivered by a ``CorrectionWriter``: ``RecordingWriter`` saves them to disk, and ``LogTenURLWriter`` hands them to LogTen only with a ``LiveWriteAuthorization``. ``BatchVerifier`` confirms each batch, ``ApplyJournal`` records it with its compensating batch, and ``LogbookBackup`` copies the whole logbook first.

## Topics

### Proposals

- ``CorrectionProposal``
- ``ApprovedCorrection``
- ``CorrectionOperation``
- ``Preflight``
- ``PreflightResult``
- ``PreflightIssue``
- ``ExcludedOperation``
- ``ManualChecklist``
- ``ManualChecklistItem``

### Packages

- ``CorrectionBatch``
- ``ImportPackage``
- ``ImportPackageMetadata``
- ``ImportEntity``
- ``ImportField``

### Delivery

- ``CorrectionWriter``
- ``RecordingWriter``
- ``LogTenURLWriter``
- ``LiveWriteAuthorization``
- ``WriteReceipt``

### Verification and journal

- ``BatchVerifier``
- ``BatchVerification``
- ``VerificationIssue``
- ``ObservedChange``
- ``ApplyJournal``
- ``ApplyJournalEntry``

### Backups

- ``LogbookBackup``
- ``BackupManifest``

### Errors

- ``CorrectionError``
