# yard-drydock-zig

Proof level: `unit-tested`

yard-drydock-zig is a Zig 0.16 drydock-arrangement kernel.
Three modules: `blocks` for the block-plan reaction distribution and
peak / total bookkeeping; `pressure` for keel-block bearing pressure
against softwood / hardwood / steel / concrete allowables; `transverse`
for the virtual rise of CG during docking (`GG_v = P l / Delta`),
residual metacentric height, and the docking stability verdict.

## What it does

### Block plan

- `blocks.averagePerBlockN(W, N)` returns `W / N`.
- `blocks.nonUniformReactionsN(densities, dx, R_out)` evaluates
  per-block reactions from a longitudinal weight density.
- `blocks.peakReactionN(R)` returns the maximum across the array.
- `blocks.totalReactionN(R)` returns the sum (= W for a consistent
  load distribution).

### Bearing pressure

- `pressure.BlockMaterial` enum (Softwood / Hardwood / Steel /
  Concrete).
- `pressure.allowablePressurePa(mat)` returns the allowable bearing
  pressure (2 / 5 / 50 / 10 MPa).
- `pressure.bearingPressurePa(R, A)` returns `R / A`.
- `pressure.pressureVerdict(p, mat)` returns pass / fail.
- `pressure.requiredAreaM2(R, mat)` returns `R / p_allow`.

### Transverse stability

- `transverse.virtualGGRiseM(P, KG, Delta)` returns `P KG / Delta`.
- `transverse.residualGMM(GM_initial, GG_v)` returns
  `GM_initial - GG_v`.
- `transverse.dockingStabilityVerdict(GM)` returns pass / fail.
- `transverse.criticalBlockForceN(W, B_residual)` returns
  `W - B_residual` (clamped to zero).

## What it is not (v0.0.0)

- No floating-dock buoyancy / pumping schedule.
- No detailed wood-block compression / settling time-history.
- No drydock-flooding rate / valve sequencing.
- No detailed 2D / 3D block layout from ship-form vertical curves.
- No earthquake / seismic-load amplification check.
- No drydock-floor structural verification.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 38/38 tests passed`.

## Public API

```zig
const yard = @import("yard_drydock");

// Block-plan reaction distribution.
var R: [10]f64 = undefined;
const densities = [_]f64{ 2.5e6, 3.0e6, 3.5e6, 3.5e6, 3.5e6,
                          3.5e6, 3.5e6, 3.0e6, 2.5e6, 2.0e6 };
try yard.blocks.nonUniformReactionsN(&densities, 8.0, &R);
const R_peak = try yard.blocks.peakReactionN(&R);

// Bearing pressure.
const p = try yard.pressure.bearingPressurePa(R_peak, 1.2);
const v = yard.pressure.pressureVerdict(p, .Hardwood);

// Docking-stability.
const P_crit = try yard.transverse.criticalBlockForceN(100.0e6, 70.0e6);
const GG_v = try yard.transverse.virtualGGRiseM(P_crit, 8.0, 70.0e6);
const GM_r = try yard.transverse.residualGMM(2.5, GG_v);
const dock_v = yard.transverse.dockingStabilityVerdict(GM_r);
```

## Validation

- Average per-block at 50 MN / 100 blocks = 500 kN.
- Uniform reaction array sums to W.
- Linearly-increasing density gives linearly-increasing reactions.
- Peak finds the maximum.
- Softwood allowable 2 MPa; hardwood 5 MPa; steel 50 MPa; concrete
  10 MPa.
- Bearing pressure 500 kN / 0.5 m^2 = 1 MPa.
- Verdict pass at exactly allowable; fail beyond.
- Required area for 500 kN on hardwood = 0.1 m^2; on steel = 0.01
  m^2.
- Required area on softer wood larger than hardwood at same load.
- Virtual GG rise at P = 1 MN, KG = 5 m, Delta = 100 MN = 0.05 m.
- GG scales linearly with P, inversely with Delta.
- Residual GM = initial - GG_v.
- Verdict pass at positive GM; fail at zero or negative.
- Critical block force = W - B_residual; clamped to zero when B
  exceeds W.
- Typed-error rejection for non-positive load / area / weight /
  block count / Delta / GM.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Watson, D. G. M. (1998). *Practical Ship Design*. Elsevier.
- Tupper, E. C. (2013). *Introduction to Naval Architecture*. 5th
  ed., Butterworth-Heinemann.
- Heger, R. (2005). *Dockmaster's Training Manual*. Heger Dry Dock.
- USN MIL-STD-1625D. *Safety Certification Program for Drydocking
  Facilities*.

## License

AGPL-3.0-or-later.
