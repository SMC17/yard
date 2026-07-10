# operability

Seakeeping operability — the ship's flight envelope.

- **criteria** — NORDFORSK 1987 general operability limiting criteria
  (RMS roll, vertical/lateral accelerations, slam and wetness
  probabilities) by ship class, the table STANAG 4154 assessments build
  on; length-dependent merchant slam criterion included.
- **events** — narrow-band Rayleigh exceedance statistics: Ochi (1964)
  slamming (forefoot emergence AND threshold impact velocity
  0.093*sqrt(gL)), deck wetness from bow-freeboard exceedance, propeller
  emergence, and per-hour event rates from the zero-upcrossing period.
- **msi** — O'Hanlon & McCauley (1974) Motion Sickness Incidence (the
  ISO 2631 lineage): 2-hour MSI from vertical acceleration and encounter
  frequency; reproduces ~50% MSI near 0.15 g at the most provocative
  frequency (~0.17 Hz).

Inputs are RMS values / spectral variances from the rao-spectrum and
seakeeping chain; outputs are pass/fail envelopes and event rates. Zero
dependencies.

Sources: NORDFORSK (1987) "Assessment of Ship Performance in a Seaway";
Ochi (1964); O'Hanlon & McCauley (1974); Faltinsen (1990) ch. 3; Lloyd,
"Seakeeping: Ship Behaviour in Rough Weather".

Proof level: unit-tested (published tables + closed-form statistics,
hand-checked).
