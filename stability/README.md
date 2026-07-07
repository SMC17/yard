# yard-stability-zig

Proof level: `unit-tested`

yard-stability-zig is a Zig 0.16 implementation of small-angle and
wall-sided righting-arm computation, free-surface correction, a
lost-buoyancy box-barge damage solver, and an IMO 2008 IS Code Part A
2.2 numerical-criteria evaluator.

## What it does

- `gz.smallAngleGZ(GM, phi)` = `GM * sin(phi)`.
- `gz.wallSidedGZ(GM, BM_T, phi)` = `(GM + 0.5 BM_T tan^2 phi) sin phi`
  (Atwood, valid until deck-edge immersion or bilge-emergence).
- `gz.rectTankIfs(l, b)` = `(1/12) l b^3` for a rectangular tank.
- `gz.fsContribution` and `gz.effectiveGM` for free-surface correction
  with a list of tanks.
- `damage.boxBargeOneCompartment` lost-buoyancy damaged-condition
  waterline for an N-equal-compartment box-barge with one flooded
  compartment and permeability mu.
- `is_code.evaluate` six numerical thresholds from 2008 IS Code Part A
  2.2 (areas under GZ, GZ at 30 deg, angle of GZ_max, GM_0) plus an
  overall pass/fail verdict.

## What it is not (v0.0.0)

- No general hull GZ computation from offsets (requires yard-hydro-zig
  composition; pending).
- No 2.3 weather criterion (phi_1 = 109 k X_1 X_2 sqrt(r s)).
- No probabilistic damage stability (SOLAS II-1 A index).
- No cross-flooding or progressive flooding.
- No grain-code or chemical-tanker overlays.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 19/19 tests passed`.

## Bench

```
zig build bench -Doptimize=ReleaseFast
```

## Public API

```zig
const yard = @import("yard_stability");

// Small-angle and wall-sided GZ.
const phi = 10.0 * std.math.pi / 180.0;
const gz_small = yard.gz.smallAngleGZ(0.6389, phi);
const gz_wall = yard.gz.wallSidedGZ(0.6389, 0.8889, phi);

// Free-surface correction.
const i_fs = yard.gz.rectTankIfs(5.0, 3.0);  // 11.25
const ggp = yard.gz.fsContribution(1000.0, 1025.0, i_fs, 60.0);
const tanks = [_]yard.gz.Tank{ .{ .rho_fluid = 1000.0, .i_fs = i_fs } };
const gm_eff = yard.gz.effectiveGM(0.6389, &tanks, 1025.0, 60.0);

// Box-barge one-compartment damage (canonical mu=1 case).
const T_d = try yard.damage.boxBargeOneCompartment(10.0, 2.0, 1.5, 3.0, 1.0);

// IS Code 2008 Part A 2.2 evaluation.
const result = try yard.is_code.evaluate(&angles_rad, &gz_samples, 0.30);
// result.overall == .pass or .fail; per-criterion verdicts in fields.
```

## Validation against codex substrate

Box-barge values cross-check against
`~/codex/sources/validation_fixtures.md` Section 2:

- Wall-sided GZ at 10 deg with GM = 0.6389, BM_T = 0.8889 returns
  approximately 0.1134 m.
- Free-surface correction with a 5 m x 3 m fresh-water tank in a
  60 m^3-displacement barge produces GG' ~ 0.183 m.
- One-of-five-compartment box-barge damage (canonical mu = 1) gives
  T_damaged = 1.875 m.

The IS Code 2008 thresholds match
`~/codex/sources/standards_machine_readable/imo_is_code_2008_intact_stability.yaml`.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0). Strongest
available claim: `stable-on-zig-0.16-today`.

## References

- Biran, A. and Lopez-Pulido, R. (2013), *Ship Hydrostatics and
  Stability*, 2nd ed., Ch. 10 to 12.
- IMO Resolution MSC.267(85) (2008 IS Code).
- Lewis, E. V. (ed.) (1988), *Principles of Naval Architecture*, Vol. I.
- Codex cross-references at `~/codex/concepts/gz-curve-wall-sided-approximation.md`,
  `~/codex/concepts/free-surface-correction.md`,
  `~/codex/concepts/lost-buoyancy-damage-stability-method.md`, and
  `~/codex/sources/validation_fixtures.md`.

## License

AGPL-3.0-or-later. See `LICENSE`.
