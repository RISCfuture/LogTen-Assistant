# ``References``

FAA airport and approach data, airport time zones and night.

## Overview

``NASRCycleStore`` downloads and caches NASR cycles as ``AirportIndex``es; ``CIFPApproachLibrary`` reads published approaches from the FAA's CIFP file. ``NightWindow`` classifies civil and currency night from ``SolarPosition``, and ``PlaceReferenceAudit`` checks the logbook's places against the reference data.

## Topics

### Airports

- ``AirportIndex``
- ``AirportReference``
- ``RunwayEndReference``
- ``NASRAirportLoader``
- ``NASRCycleStore``
- ``ReferenceDataError``
- ``PlaceReferenceAudit``

### Time zones

- ``AirportTimeZones``
- ``AirportTimeZone``
- ``TimeZoneSource``
- ``TimeZoneResolving``
- ``MapKitTimeZoneResolver``

### Approaches

- ``ApproachLookup``
- ``CIFPApproachLibrary``
- ``PublishedApproach``
- ``ApproachFix``
- ``ApproachFamily``

### Night

- ``NightWindow``
- ``NightClassification``
- ``SolarPosition``
