# yard-keel-zig

Proof level: `unit-tested`

yard-keel-zig is a Zig 0.16 sailing-yacht keel and rudder appendage
kernel per Larsson and Eliasson 2014. Effective aspect ratio for a
surface-piercing foil, lifting-line lift coefficient `C_L = 2 pi alpha
AR / (AR + 2)`, induced-drag coefficient `C_Di = C_L^2 / (pi AR)`,
and dimensional side force / induced drag.

## What it does

- `appendage.effectiveAspectRatio(h, S)` returns `h^2 / S` with the
  free-surface-mirror doubling already baked into the geometric
  span as the effective span.
- `appendage.liftCoefficient(alpha, AR)` returns
  `2 pi alpha AR / (AR + 2)`.
- `appendage.inducedDragCoefficient(C_L, AR)` returns
  `C_L^2 / (pi AR)`.
- `appendage.sideForceN(rho, V, S, C_L)` returns
  `0.5 rho V^2 S C_L`.
- `appendage.inducedDragN(rho, V, S, C_Di)` returns
  `0.5 rho V^2 S C_Di`.

## What it is not (v0.0.0)

- No bulb-keel / wing-keel induced-drag reduction.
- No transverse-cant cant-angle compensation.
- No DSYHS (Delft Systematic Yacht Hull Series) bare-hull regression.
- No sail-trim / VPP coupling (output composes with a VPP loop
  externally).
- No frictional drag on the appendage (compose with ITTC-57 in
  `yard-resistance-zig`).
- No fluid-structure-interaction flex coupling on long-fin keels.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 13/13 tests passed`.

## Public API

```zig
const yard = @import("yard_keel");

const AR = try yard.appendage.effectiveAspectRatio(2.0, 1.0);
const alpha = 5.0 * std.math.pi / 180.0;
const C_L = try yard.appendage.liftCoefficient(alpha, AR);
const C_Di = try yard.appendage.inducedDragCoefficient(C_L, AR);
const F = try yard.appendage.sideForceN(1025.0, 5.0, 2.0, C_L);
const D = try yard.appendage.inducedDragN(1025.0, 5.0, 2.0, C_Di);
```

## Validation

- AR for h = 2 m, S = 1 m^2 equals 4.
- Lift coefficient closed form at alpha = 5 deg, AR = 4.
- Lift slope `dC_L / d alpha = 2 pi AR / (AR + 2)`.
- High-AR limit approaches the thin-airfoil 2 pi slope.
- Low-AR foil gives smaller lift than high-AR foil at the same
  alpha.
- Induced drag scales with `C_L^2`.
- At AR = pi the induced-drag formula reduces to `C_L^2 / pi^2`.
- Side force scales with `V^2`.
- Induced-drag-to-lift ratio is much smaller than unity at small
  alpha.
- Typed-error rejection for zero AR / S / V, alpha >= pi/2.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Larsson, L., Eliasson, R. E., Orych, M. (2014). *Principles of
  Yacht Design*. 4th ed., Adlard Coles.
- Hoerner, S. F. (1965). *Fluid-Dynamic Drag*. Hoerner Fluid Dynamics.
- Whicker, L. F., Fehlner, L. F. (1958). *Free-Stream Characteristics
  of a Family of Low-Aspect Ratio, All-Movable Control Surfaces*.
  DTMB Report 933.
- Anderson, J. D. (2017). *Fundamentals of Aerodynamics*. 6th ed.,
  McGraw-Hill.

## License

Apache-2.0.
