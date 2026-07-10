# yard-port-engineering-zig

Proof level: `unit-tested`

Port-engineering kernel: rubble-mound breakwater wave transmission + Hudson
armour-stone + Iribarren run-up; PIANC channel depth + Barrass squat +
manoeuvring-class two-way width; harbour basin Helmholtz + Merian seiche
resonance.

## What it does

- `breakwater` — K_t transmission, Hudson W_50, Iribarren ξ, Hunt 1959 run-up.
- `channel` — UKC levels (exposed/inner/dock), Barrass squat, gross depth,
  two-way channel width.
- `basin` — Helmholtz period, closed-closed and closed-open Merian seiche
  periods, 5 % resonance verdict.

## What it is not

Not coastal FEM, wave-structure interaction CFD, or detailed breakwater
cross-section design software. Hudson and transmission formulas are empirical
correlations within stated validity — not a substitute for physical model
tests or site-specific wave climate studies. Not a dredging cost estimator or
environmental impact assessment tool.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 40/40 tests passed`.

## References

- Hudson, R. Y. (1959). *Laboratory Investigation of Rubble-Mound Breakwaters*.
  ASCE Waterways and Harbors Division.
- Goda, Y., Ahrens, J. P. (1982). *New Wave Transmission Formula for Submerged
  Breakwaters*.
- Barrass, C. B. (1979). *A Unified Approach to Squat Calculations for Ships*.
  PIANC Bulletin.
- PIANC Working Group 49. *Harbour Approach Channels Design Guidelines*.
- Merian, J. R. (1828). *Ueber die Bewegung tropfbarer Fluessigkeiten*.

## License

Apache-2.0. See `LICENSE`.