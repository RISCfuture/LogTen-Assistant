# ``Regulations``

Checks a logbook against the pilot currency regulations of 14 CFR part 61.

## Overview

``RegulationEngine`` evaluates the eleven ``RegulationRule``s for a pilot's profile. A rule that doesn't apply to the pilot is skipped, and one whose custom fields aren't mapped is reported as not evaluated rather than passed, through ``RuleStatus``.

## Topics

### Evaluating

- ``RegulationEngine``
- ``RegulationReport``
- ``FlightViolations``
- ``Violation``

### Rules

- ``RegulationRule``
- ``RuleStatus``
- ``RuleSkipReason``
