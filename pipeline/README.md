# yard-pipeline-zig

Proof level: `unit-tested`

yard-pipeline-zig is a Zig 0.16 subsea-pipeline on-bottom-stability
kernel per DNV-RP-F109 (simplified Morison + lateral static balance).
Per-unit-length drag, inertia, and lift forces from Morison; required
submerged weight from `(F_D + F_I) SF / mu + F_L`.

## What it does

- `stability.dragForcePerLengthNM(rho, C_D, D, U)` returns
  `0.5 rho C_D D U|U|`.
- `stability.inertiaForcePerLengthNM(rho, C_M, D, dU/dt)` returns
  `rho C_M (pi D^2 / 4) dU/dt`.
- `stability.liftForcePerLengthNM(rho, C_L, D, U)` returns
  `0.5 rho C_L D U^2`.
- `stability.requiredSubmergedWeightNM(F_D, F_I, F_L, mu, SF)` returns
  the required submerged weight per unit length.
- `stability.verdict(W_actual, W_required)` pass / fail.

## What it is not (v0.0.0)

- No long-term wave-statistics Hs / Tp envelope (caller supplies
  representative U and dU/dt).
- No vortex-induced vibration (VIV) gate.
- No span-shoulder / free-span fatigue check.
- No bottom-shape soft-soil correction (rigid-bottom friction only).
- No flexural rigidity / lateral buckle initiation.
- No pipe wall stress check (compose with DNV-OS-F101 strength
  module externally).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 20/20 tests passed`.

## oceanman cable route consumer

`src/cable_route_consumer.zig` reads an oceanman per-cable JSON record
(TeleGeography v3 snapshot; see `~/oceanman/data/snapshots/2026-05-07/
SCHEMA.md`) and emits a geometry-only `LayPlan`: waypoints, great-
circle segment lengths, and a `depth_profile_present` flag.

Run the smoke gate against a fixed cable id:

```
./scripts/oceanman_smoke.sh                          # aden-djibouti default
OCEANMAN_CABLE_ID=2africa ./scripts/oceanman_smoke.sh
```

Expected: 30-run median parse time well under the 100 ms gate.

### Substrate-shared, not identical (load-bearing disclosure)

A submarine telecommunications cable record is NOT a subsea-pipeline
lay plan. The wire surfaces the SHARED route-geometry substrate only
(maritime great-circle waypoints, segment lengths, landfall
constraints). It does NOT transfer per-KP bathymetry, soil
classification, vessel tension envelope (S-lay / J-lay / reel-lay), or
the DNV-RP-F109 on-bottom-stability gate. The `depth_profile_present`
field on `LayPlan` is the honest signal: v0.0 always emits false
because the oceanman corpus does not ship per-KP bathymetry.

## Public API

```zig
const yard = @import("yard_pipeline");

const FD = try yard.stability.dragForcePerLengthNM(1025.0, 1.2, 0.5, 2.0);
const FI = try yard.stability.inertiaForcePerLengthNM(1025.0, 2.0, 0.5, 1.0);
const FL = try yard.stability.liftForcePerLengthNM(1025.0, 0.9, 0.5, 2.0);
const W_req = try yard.stability.requiredSubmergedWeightNM(
    FD, FI, FL, 0.5, 1.1);
const v = yard.stability.verdict(W_actual, W_req);
```

## Validation

- Drag F_D at rho = 1025, C_D = 1.2, D = 0.5 m, U = 2 m/s equals
  1230 N/m closed form.
- Direction preserved via `U |U|` (negative U flips sign).
- Inertia F_I matches `rho C_M (pi D^2 / 4) dU/dt` to 1e-9.
- Lift F_L at C_L = 0.9, U = 2 m/s equals 922.5 N/m.
- Required submerged weight worked example: 3628.5 N/m.
- W scales linearly in safety factor and inversely in friction
  (drag term).
- Verdict pass at exactly required weight; fail when actual <
  required.
- Typed-error rejection for non-positive density, zero coefficient,
  zero friction.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- DNV-RP-F109. *On-Bottom Stability Design of Submarine Pipelines*.
- DNV-OS-F101. *Submarine Pipeline Systems*.
- Morison, J. R., O'Brien, M. P., Johnson, J. W., Schaaf, S. A.
  (1950). *The Force Exerted by Surface Waves on Piles*.
  Petroleum Transactions AIME 189.
- Sumer, B. M., Fredsoe, J. (2006). *Hydrodynamics around Cylindrical
  Structures*. World Scientific.

## License

AGPL-3.0-or-later.
