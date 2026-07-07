# yard-savitsky-zig

Proof level: `unit-tested`

yard-savitsky-zig is a Zig 0.16 planing-hull lift kernel implementing
the Savitsky 1964 empirical formulation for a prismatic V-bottom
hull. The flat-plate coefficient `C_L0(tau, lambda, C_V)` and the
deadrise reduction `C_Lbeta = C_L0 - 0.0065 beta C_L0^0.6` form the
basis for force-balance trim solving and lift evaluation against a
displacement weight.

## What it does

- `savitsky.speedCoefficient(V, B, g)` returns the beam Froude
  C_V = V / sqrt(g B).
- `savitsky.flatPlateLiftCoefficient(tau_deg, lambda, C_V)` the flat-
  plate empirical fit, range-gated to the Savitsky-valid domain
  2 deg <= tau <= 15 deg and 1 <= lambda <= 4.
- `savitsky.veeBottomLiftCoefficient(C_L0, beta_deg)` deadrise
  reduction.
- `savitsky.hydrodynamicLiftN(rho, V, B, C_Lbeta)` lift force.
- `savitsky.solveTrimDeg(W, B, V, rho, beta_deg, lambda, g)` bisection
  inverse solver for the trim angle that satisfies vertical force
  balance against a displacement weight.

## What it is not (v0.0.0)

- No frictional drag (caller composes with `yard-resistance-zig` or
  the ITTC-57 friction line).
- No trim moment / equilibrium with shaft thrust line.
- No spray-rail / chine-strip correction.
- No wave / sea-state response (steady-water only).
- No deep-vee (beta > 30 deg) extrapolation.
- No high-speed Froude-corrected regime (C_V > ~10 unverified).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 14/14 tests passed`.

## Public API

```zig
const yard = @import("yard_savitsky");

const C_V = try yard.savitsky.speedCoefficient(15.0, 3.0, 9.81);
const C_L0 = try yard.savitsky.flatPlateLiftCoefficient(4.0, 2.0, C_V);
const C_Lb = try yard.savitsky.veeBottomLiftCoefficient(C_L0, 15.0);
const L = try yard.savitsky.hydrodynamicLiftN(1025.0, 15.0, 3.0, C_Lb);

const tau = try yard.savitsky.solveTrimDeg(
    98_100.0, 3.0, 15.0, 1025.0, 15.0, 2.0, 9.81);
```

## Validation

- C_V = V / sqrt(g B) closed form.
- C_L0 at tau=4, lambda=2, C_V=4 matches manual expansion to 1e-12.
- C_L0 monotone increasing in tau, monotone decreasing in C_V.
- C_Lbeta at beta=0 equals C_L0; at beta=20 the closed-form formula
  reproduces 0.0673554 from 0.10 input.
- Vee-bottom reduction clamps to zero on degenerate inputs.
- Lift force 0.5 rho V^2 B^2 C_Lbeta closed form.
- Trim-solver inverse: solved trim reproduces input weight to 100 N
  on a 98.1 kN test case.
- Typed-error rejection for trim outside [2, 15] deg, lambda outside
  [1, 4], deadrise outside [0, 30] deg, non-positive beam.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Savitsky, D. (1964). *Hydrodynamic Design of Planing Hulls*. Marine
  Technology 1(1).
- Savitsky, D., Brown, P. W. (1976). *Procedures for Hydrodynamic
  Evaluation of Planing Hulls in Smooth and Rough Water*. Marine
  Technology 13(4).
- Faltinsen, O. (2005). *Hydrodynamics of High-Speed Marine Vehicles*.
  Cambridge.

## License

AGPL-3.0-or-later.
