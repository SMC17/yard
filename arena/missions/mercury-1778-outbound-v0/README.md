# Mercury Outbound, 1778

Proof level: empirical reference path `integration-tested`; exact ship and
daily-log reconstruction `scaffold`.

An era-constrained counterfactual fleet-design mission based on the documented
1778-1779 outward voyage of the English East India Company ship *Mercury* from
the Downs to Bombay/Mumbai via St Helena and Table Bay.

The route anchors are historical. The reference fleet and resource-credit
economics are explicit counterfactual inputs, not claims about *Mercury* or
eighteenth-century prices. `yard-mercury` runs 256 deterministic scenarios over
the checked-in CLIWOC ensemble and produces the trusted result plus replay.

The QDL catalogue records the Downs on 14 December 1778 and Bombay on 18 July
1779, a 216-day interval. The current empirical reference fleet produces a
204.1-day mean and 251.3-day p95. That is a calibration signal, not validation
of the hull or sailed trajectory.

## Sources selected for the full pack

- [Mercury journal, 1777-1784](https://www.qdl.qa/en/archive/81055/vdc_100113993973.0x00005b), British Library/Qatar Digital Library, Open Government Licence.
- [CLIWOC 2.1](https://doi.org/10.1594/PANGAEA.743343), CC BY 3.0 historical ship-log weather observations.
- [Chapman shipbuilding treatise](https://www.loc.gov/item/14021345/), Library of Congress public-domain scan of an 1820 English translation of the 1775 work.
- [Smithsonian *Brilliant* ship-model metadata](https://www.si.edu/object/ship-model-tobacco-ship-brilliant%3Anmah_844307), CC0 metadata; images are not redistributed.
- [USDA Wood Handbook](https://research.fs.usda.gov/fpl/wood-handbook), official material-property reference; per-file notices must be retained.

The checked-in CLIWOC derivative contains 76,184 selected observations across
route legs and calendar months. It supplies an empirical ensemble, not exact
gridded weather. Chapman and
*Brilliant* provide period constraints and sanity checks, not a reconstruction
of *Mercury*. Historical and current place names remain paired.

`log/route-anchors.v0.json` records five catalogue-derived OGL anchors with
folio references and confidence. It deliberately stores no invented raw-page
transcription. Daily course, wind, remarks, and cargo transcription remain the
next source-review gate.

This is a civilian logistics and crew-safety challenge. It does not model
weapons, conquest, or extraction as objectives. The mission documentation must
retain the East India Company's colonial and coercive context rather than
present it as a neutral shipping firm.
