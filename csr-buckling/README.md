# yard-csr-buckling-zig

Proof level: `unit-tested`

yard-csr-buckling-zig is a Zig 0.16 plate and column buckling kernel
covering the elastic critical stress formulas adopted by IACS Common
Structural Rules Section 8 and DNV-RP-C201. Two modules: `plate` for
thin-plate compressive and shear buckling, `column` for Euler critical
load and Johnson-parabola short-column reduction.

## What it does

- `plate.bucklingCoefficient(boundary, loading, alpha)` returns the
  classical plate coefficient `k` for simply-supported or clamped
  edges under uniaxial compression or shear.
- `plate.elasticCriticalStressPa(E, nu, t, b, k)` evaluates
  sigma_cr = k pi^2 E / (12 (1 - nu^2)) (t/b)^2.
- `plate.johnsonReducedStressPa(sigma_cr, sigma_y)` applies the CSR
  Section 8.2.2 Johnson-parabola reduction when sigma_cr exceeds
  half the yield stress: sigma_eff = sigma_y (1 - sigma_y/(4 sigma_cr)).
- `column.effectiveLengthFactor(end)` returns mu for pinned-pinned
  (1.0), fixed-pinned (0.7), fixed-fixed (0.5), fixed-free (2.0).
- `column.eulerCriticalLoadN(E, I, L, end)` returns
  P_cr = pi^2 E I / (mu L)^2.
- `column.eulerCriticalStressPa(E, I, A, L, end)` returns
  sigma_cr = P_cr / A.
- `column.slendernessRatio(I, A, L, end)` returns lambda = mu L /
  sqrt(I/A).
- `column.eulerCriticalStressFromLambdaPa(E, lambda)` returns
  pi^2 E / lambda^2 for direct slenderness inputs.

## What it is not (v0.0.0)

- No torsional / flexural-torsional buckling of open thin-walled
  sections (CSR Section 8.3 / RP-C201 6).
- No stiffened-panel orthotropic buckling (CSR Section 8.4).
- No biaxial / combined loading interaction curves
  (CSR Section 8.2.4).
- No imperfection sensitivity / Perry-Robertson reduction.
- No plate-girder web-shear post-buckling (CSR Section 9).
- No code-specific safety factors (caller applies usage factor /
  permissible stress ratios externally).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 24/24 tests passed`.

## Public API

```zig
const yard = @import("yard_csr_buckling");

// Plate buckling
const k = try yard.plate.bucklingCoefficient(
    .simply_supported_4_edges, .uniaxial_compression, 1.5);
const sigma_cr = try yard.plate.elasticCriticalStressPa(
    210e9, 0.3, 10e-3, 500e-3, k);
const sigma_eff = try yard.plate.johnsonReducedStressPa(sigma_cr, 355e6);

// Column buckling
const P_cr = try yard.column.eulerCriticalLoadN(
    210e9, 1e-6, 3.0, .pinned_pinned);
const lambda = try yard.column.slendernessRatio(1e-6, 1e-3, 3.0, .pinned_pinned);
```

## Validation

- SS plate uniaxial compression `k` = 4 at alpha = 1, 4 at alpha = 2.
- Clamped plate uniaxial compression `k` ~ 7 asymptote, 8 at alpha = 1.
- SS plate shear `k` = 9.34 at alpha = 1.
- Clamped plate shear `k` = 14.58 at alpha = 1.
- Steel plate sigma_cr at E=210 GPa, nu=0.3, t/b=1/50, k=4 lies in
  [300, 310] MPa.
- sigma_cr scales as (t/b)^2.
- Johnson reduction: sigma_cr below 0.5 sigma_y unchanged; sigma_cr =
  500 MPa with sigma_y = 235 MPa gives sigma_eff = 207.3875 MPa.
- Effective length: P_cr fixed-fixed / pinned-pinned = 4.0;
  fixed-free / pinned-pinned = 0.25; fixed-pinned slenderness / pinned-pinned = 0.7.
- Typed-error rejection for non-positive dimensions, invalid Poisson
  ratio, aspect ratio below 1.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IACS Common Structural Rules for Bulk Carriers and Oil Tankers
  Section 8 (Buckling).
- DNV-RP-C201 Buckling Strength of Plated Structures.
- Timoshenko, S. P., Gere, J. M. (1961). *Theory of Elastic
  Stability*. McGraw-Hill.
- Bleich, F. (1952). *Buckling Strength of Metal Structures*.
  McGraw-Hill.

## License

Apache-2.0.
