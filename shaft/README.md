# yard-shaft-zig

Proof level: `unit-tested`

yard-shaft-zig is a Zig 0.16 torsional-vibration kernel for marine
shaftlines. Implements the classical Holzer (1921) tabular method
for free-free torsional natural-frequency extraction on a lumped
inertia-and-spring chain, together with a closed-form torsional-
stiffness module for solid / hollow circular shaft segments.

## What it does

### Holzer free-free natural-frequency search

- `holzer.holzerResidual(J, k, omega)` propagates phi and T through
  the chain using `phi_{i} = phi_{i-1} - T_{i-1}/k_{i-1}` and
  `T_i = T_{i-1} + J_i omega^2 phi_i`. Returns the residual torque
  at the far end; a natural frequency is the omega at which the
  residual vanishes.
- `holzer.findNaturalFrequency(J, k, lo, hi)` brackets a sign change
  of the residual and refines via bisection.

### Shaft stiffness

- `shaft_stiffness.polarSolidM4(D)` returns `pi D^4 / 32` polar second
  moment of area.
- `shaft_stiffness.polarHollowM4(D_o, D_i)` returns
  `pi (D_o^4 - D_i^4) / 32`.
- `shaft_stiffness.torsionalStiffnessNmPerRad(G, J, L)` returns the
  segment stiffness `G J / L`.
- `shaft_stiffness.polarMassInertiaSolidKgm2(D, L, rho)` returns the
  polar mass moment of inertia of a solid cylindrical segment.

## What it is not (v0.0.0)

- No damped-vibration response (free-free undamped only).
- No automatic multi-mode bracketing (caller chooses the search
  bracket).
- No transfer-matrix method for non-uniform inertias / multi-line
  branches.
- No shaft-bending whirl / Lateral vibration analysis.
- No coupled propeller-water added-mass coupling.
- No torsional fatigue life (compose with `yard-csr-fatigue-zig`).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 19/19 tests passed`.

## Public API

```zig
const yard = @import("yard_shaft");

// Two-inertia shaftline: J_1 = 10 kg m^2, J_2 = 5 kg m^2,
// connected by torsional stiffness k = 1e6 Nm/rad.
const J = [_]f64{ 10.0, 5.0 };
const k = [_]f64{1.0e6};
const omega_1 = try yard.holzer.findNaturalFrequency(&J, &k, 100.0, 1000.0);

// Closed-form torsional stiffness of a steel solid shaft.
const J_poly = try yard.shaft_stiffness.polarSolidM4(0.5);
const k_torsional = try yard.shaft_stiffness.torsionalStiffnessNmPerRad(
    80e9, J_poly, 5.0);
```

## Validation

- Two-inertia free-free system reproduces the classical
  `omega_1 = sqrt(k (J_1 + J_2) / (J_1 J_2)) = 547.72 rad/s` to 1e-4
  rad/s.
- Holzer residual is zero (< 1e-6) at the analytic natural frequency.
- Residual sign changes between low and high omega.
- Three-inertia system convergence on the lowest mode.
- Solid polar J at D = 0.5 m matches `pi 0.0625 / 32` to 1e-15.
- Polar J scales with D^4 (ratio 16 for D ratio 2).
- Hollow J at D_i = 0 equals solid J.
- Torsional stiffness scales inversely with length (1/2 for 2x L).
- Polar mass inertia scales linearly with length.
- Typed-error rejection for insufficient stations, unequal length,
  non-positive inertia / stiffness / omega / diameter / length,
  invalid hollow geometry, and bracket without a sign change.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Holzer, H. (1921). *Die Berechnung der Drehschwingungen*.
  Springer.
- Den Hartog, J. P. (1956). *Mechanical Vibrations*. McGraw-Hill,
  Chapter 4.
- Vance, J. M. (1988). *Rotordynamics of Turbomachinery*. Wiley.

## License

Apache-2.0.
