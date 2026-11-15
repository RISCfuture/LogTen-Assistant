# LogTen import validation

What LogTen Pro does with the `logten://v2/addEntities` import, as validated against the
installed app. The corrections allowlist (`ImportField`) and the batch verifier
(`BatchVerifier`) encode these results.

## Setup

- Date: 2026-11-06
- LogTen Pro: 2026.5.0 (build 16709)
- Data model: `CNLogBookDocument2026`
- Method: the app created test flights with app-owned flight keys, audited them, and corrected
  them through its own `ApplyPlan`, `ImportPackage`, `LogTenURLWriter` and `BatchVerifier`. The
  flights were then probed with further imports and removed with `modifyEntities` and
  `removeEntities`. A backup was taken first, and the flights, places, aircraft and people were
  identical afterwards.

## Fields verified through create and modify

| Field | Written as |
| --- | --- |
| `flight_sic`, `flight_solo`, `flight_p1us`, `flight_dualGiven`, `flight_dualReceived` | `H:MM` |
| `flight_crossCountry`, `flight_actualInstrument`, `flight_simulatedInstrument` | `H:MM` |
| `flight_picNight`, `flight_sicNight`, `flight_p1usNight` | `H:MM` |
| `flight_dualReceivedNight`, `flight_crossCountryNight` | `H:MM` |
| `flight_hobbsStart`, `flight_hobbsStop`, `flight_tachStart`, `flight_tachStop` | number |
| `flight_to`, `flight_from` | the identifier text of an existing place |

A place identifier resolves to the existing place, and no place is created.

## Behaviours

- **Clearing stores zero.** Sending JSON `null` for a minute or count field stores `0`, not
  null. The verifier treats null and zero as equal for those fields.
- **LogTen recomputes derived fields on import.** The verifier allows these as side effects, and
  only when a change to the same flight explains them:
  - `flight_sicCapacity` was false when SIC was cleared to zero and true when it was set above
    zero. `flight_picCapacity` follows PIC time in the same way.
  - `flight_specialNightFlags`, a bit field, changed when night role times changed.
  - `flight_totalInstrument` is actual plus simulated instrument time.
  - The numbered `flight_category`, `flight_aircraftClass` and `flight_engineType` totals follow
    total time. Observed: `category1`, `aircraftClass2` and `engineType1`, `2` and `7` went from
    60 to 30 with total time. The verifier allows any numbered attribute of the three to change
    to the new total.
- **Lowering total time clamps role times.** Setting total time below a role time silently
  lowers that role: PIC went from 60 to 30 when total went from 60 to 30. On creation LogTen
  also limited solo, cross-country, actual instrument and dual given to total, but not
  simulated instrument. Corrections that lower total time therefore include a change limiting
  each of PIC, SIC, P1 u/s, solo, dual given, dual received, night, cross-country, actual
  instrument and simulated instrument that exceeds the new total, so what the reviewer approves
  is what happens.
- **Night is not raised on modify.** Setting night below PIC night stores it as sent, with a
  "Night could not be calculated" warning. On create, LogTen raised night to cover the night
  role times.
- **From is filled in on created flights.** LogTen filled in From on created flights that
  didn't specify one.
- **Hobbs and tach are single-precision floats.** They read back as `1233.4000244140625` for
  `1233.4`. The reader maps them to the decimal that was typed, and the verifier compares
  numbers at single precision.
- **Every import needs the user's confirmation.** LogTen asks once per import, and counts
  flights per dialog.
