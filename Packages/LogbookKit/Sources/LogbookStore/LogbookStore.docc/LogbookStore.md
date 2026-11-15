# ``LogbookStore``

Finds LogTen logbooks, snapshots them, and reads the snapshots.

## Overview

The live store is never opened. ``LogbookSnapshotter`` copies the store and its WAL under file coordination, checks the copy is stable, then checkpoints and verifies it. ``LogbookReader`` opens only snapshots, read-only, with LogTen's installed data model (``LogTenModel``), and refuses a store whose model differs rather than migrating it.

## Topics

### Locating logbooks

- ``LogbookLocation``
- ``LogTenModel``

### Snapshots

- ``LogbookSnapshotter``
- ``LogbookSnapshot``
- ``SnapshotFileState``

### Reading

- ``LogbookReader``
- ``LogbookStoreError``
