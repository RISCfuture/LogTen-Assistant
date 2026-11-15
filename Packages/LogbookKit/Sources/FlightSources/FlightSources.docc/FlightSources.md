# ``FlightSources``

Evidence from FlySto and ADS-B archives.

## Overview

``FlyStoClient`` syncs logs from FlySto's public API incrementally and uploads data logs; ``FlyStoCSVImporter`` reads FlySto's CSV export, optionally with ``FlyStoLinkIndex`` links from a saved web archive. Both produce ``FlyStoRecord``s. ``ADSBLolClient`` streams adsb.lol's daily archives, keeping only the wanted aircraft, into an ``ADSBTraceCache``; ``OpenSkyClient`` reads recent tracks from the OpenSky Network.

## Topics

### FlySto

- ``FlyStoClient``
- ``FlyStoLog``
- ``FlyStoLogPage``
- ``FlyStoLogEvent``
- ``FlyStoParameter``
- ``FlyStoValue``
- ``FlyStoUpload``
- ``FlyStoProcessing``
- ``FlyStoCrewEntry``
- ``ZipArchive``

### FlySto records

- ``FlyStoRecord``
- ``FlyStoTimes``
- ``FlyStoTimeKind``
- ``FlyStoCounts``
- ``FlyStoCountKind``
- ``FlyStoField``
- ``FlyStoTimeIssue``
- ``FlyStoMetrics``
- ``FlyStoCrewMember``
- ``FlyStoRunwayEvent``
- ``FlyStoRow``
- ``FlyStoRejection``

### FlySto exports

- ``FlyStoCSVImporter``
- ``FlyStoExport``
- ``FlyStoLinkIndex``

### ADS-B

- ``ADSBLolClient``
- ``ADSBRelease``
- ``ADSBArchiveDay``
- ``ADSBFetchProgress``
- ``ADSBRetryPolicy``
- ``ADSBRetry``
- ``ADSBRetryReason``
- ``ADSBTransferError``
- ``ADSBFetchResult``
- ``ADSBTraceFile``
- ``ADSBProvenance``
- ``ADSBTraceCache``
- ``OpenSkyClient``
- ``OpenSkyFlight``
- ``OpenSkyTrackSource``

### Networking

- ``HTTPTransport``
- ``URLSessionTransport``
- ``FlightService``
- ``FlightSourceError``
