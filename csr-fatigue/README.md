# yard-csr-fatigue-zig

Proof level: `unit-tested`

yard-csr-fatigue-zig is a Zig 0.16 fatigue-assessment kernel covering
DNV-RP-C203 bilinear S-N curves (air environment) and Palmgren-Miner
linear cumulative damage. Fourteen detail classes from B1 to W3,
thickness reduction for plates above the reference 25 mm, per-block
applied-versus-permissible damage sum, and remaining-life
extrapolation.

## What it does

- `sn.DetailClass` enum of fourteen DNV-RP-C203 detail classes (B1,
  B2, C, C1, C2, D, E, F, F1, F3, G, W1, W2, W3).
- `sn.DetailClass.params()` returns the `(m_1, log_a_1, m_2, log_a_2,
  t_ref, k)` six-tuple from RP-C203 Table 2-1 (air).
- `sn.kneeStressMPa(p)` knee-point stress where the slope changes from
  m_1 to m_2 at log N = 7.0.
- `sn.cyclesToFailure(cls, delta_sigma_mpa, thickness_mm)` evaluates
  the bilinear log-log S-N curve with thickness reduction (t / t_ref)^k
  applied when thickness exceeds the reference value.
- `miner.cumulativeDamage(n_applied, N_permissible)` Palmgren-Miner
  sum D = sum_i n_i / N_i.
- `miner.verdict(D)` returns `.pass` if D < 1.0, `.fail` otherwise.
- `miner.remainingLifeFromCurrentBlock(D, n_total)` extrapolates the
  remaining-life cycles assuming linear repetition of the current
  stress block sequence.

## What it is not (v0.0.0)

- No seawater-with-cathodic-protection or free-corrosion environment
  detail-class catalogue (only the in-air slopes from Table 2-1).
- No rainflow stress-block decomposition (caller supplies block-wise
  (delta_sigma, n) histogram).
- No probabilistic / mean-stress (Goodman, Soderberg) correction.
- No notch-stress / hot-spot stress concentration factor library;
  caller passes nominal delta_sigma already including K_t / K_s
  effects.
- No principal-stress reorientation; caller resolves multi-axial
  stress to a uniaxial range before invoking the kernel.
- No automatic spectrum-to-block converter (compose with
  `yard-rao-spectrum-zig` plus a stress-range histogram step).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 20/20 tests passed`.

## Public API

```zig
const yard = @import("yard_csr_fatigue");

// S-N curve evaluation.
const N = try yard.sn.cyclesToFailure(.D, 160.0, 25.0);
const ds_knee = yard.sn.kneeStressMPa(yard.sn.DetailClass.D.params());

// Miner sum over a stress-block histogram.
const n_applied = [_]f64{ 1e6, 5e5, 2e5 };
const N_perm    = [_]f64{ 1e7, 5e6, 5e5 };
const D = try yard.miner.cumulativeDamage(&n_applied, &N_perm);
const v = yard.miner.verdict(D);
const remaining = yard.miner.remainingLifeFromCurrentBlock(D, 1.7e6);
```

## Validation

- D class knee stress: 52.63 MPa to 0.05 MPa.
- D class at 160 MPa (above knee, m_1 = 3) and 30 MPa (below knee,
  m_2 = 5) match the closed-form bilinear log-log formula to within
  one cycle.
- Knee stress maps to N = 1e7 to 1e3.
- C class is more durable than D at the same stress.
- W3 is the least durable of the listed classes.
- Thickness reduction at t = 50 mm vs t_ref = 25 mm for D class
  (k = 0.2) gives N_ref / N_thick = (50/25)^(0.2 * 3) ~ 1.149^3 to
  0.05.
- Miner sum: single-block 1e6/1e7 = 0.1 verdict `.pass`; sum of 1.5
  verdict `.fail`; sum exactly 1.0 verdict `.fail`.
- Remaining life: D = 0.5, n_total = 1e6 -> 1e6 remaining; D = 0 ->
  infinite; D = 1 -> 0.
- Typed errors for unequal-length, non-positive cycles, non-positive
  stress, non-positive thickness, empty input.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- DNV-RP-C203 Fatigue Design of Offshore Steel Structures
  (2024 edition).
- IACS Common Structural Rules for Bulk Carriers and Oil Tankers
  Section 9 (Fatigue).
- Palmgren, A. (1924). *Die Lebensdauer von Kugellagern*. VDI Zeit.
- Miner, M. A. (1945). *Cumulative Damage in Fatigue*.
  J. Applied Mechanics 12.

## License

Apache-2.0.
