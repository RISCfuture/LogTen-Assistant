# Changelog

Release notes for LogTen Assistant. The version headings are what
`Scripts/release-notes.sh` reads, and what the Release workflow attaches to a
GitHub release — so a heading is `## <version>`, matching the tag exactly.

## 1.0

### New

- Audit a LogTen logbook in its own window per logbook. The app reads only
  snapshot copies of the logbook, never the live store.
- Audit & Fix compares entries with each other, with the logbook's smart groups,
  and with what the aircraft recorded, then proposes fixes for you to review and
  approve.
- Violations lists the flights that break the pilot-currency rules of 14 CFR
  part 61. It only reports; nothing is corrected.
- Sync flight logs from FlySto with an API token, or import a FlySto CSV export.
- Fetch ADS-B traces for your aircraft from adsb.lol, and OpenSky as a further
  source.
- Update FAA airport and approach data from the current 28-day cycle.
- Apply approved fixes through LogTen's import, behind a preflight check, a
  verified backup of the logbook folder and a one-flight pilot batch. Each
  batch is verified afterwards and can be reverted.
- Fill in the pilot profile from the FAA airmen database.
- Check for new versions of the app from GitHub.
