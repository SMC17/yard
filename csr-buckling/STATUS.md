# Status

yard-csr-buckling-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `plate.bucklingCoefficient` | `unit-tested` | k=4 at alpha=1,2 SS-compression; k=9.34 alpha=1 SS-shear; k=14.58 alpha=1 clamped-shear |
| `plate.elasticCriticalStressPa` | `unit-tested` | 304 MPa for steel t/b=1/50 SS plate; (t/b)^2 scaling exact |
| `plate.johnsonReducedStressPa` | `unit-tested` | passthrough below 0.5 sigma_y; 207.3875 MPa for sigma_cr=500, sigma_y=235 |
| `column.effectiveLengthFactor` | `unit-tested` | 1.0/0.7/0.5/2.0 for the four classical end conditions |
| `column.eulerCriticalLoadN` | `unit-tested` | pi^2 for E=I=L=1 pinned-pinned; F-F/P-P = 4; F-Free/P-P = 1/4 |
| `column.eulerCriticalStressPa` | `unit-tested` | 230 MPa for steel I=1e-6, A=1e-3, L=3 m |
| `column.slendernessRatio` | `unit-tested` | mu L / sqrt(I/A); F-P/P-P ratio = 0.7 |
| `column.eulerCriticalStressFromLambdaPa` | `unit-tested` | pi^2 E / lambda^2 closed form |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `24/24 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: typed-error rejection for non-positive
  thickness, length, area, modulus, or yield; invalid Poisson ratio
  outside (0, 0.5); aspect ratio below 1.
- Type-II missed risk guard: Johnson-parabola branch ensures sigma_cr
  above 0.5 sigma_y is not reported at face value; the kernel honours
  the inelastic reduction.
- Type-III category guard: scalar critical-stress kernel only; not a
  stiffened-panel orthotropic solver; not a torsional / flexural-
  torsional buckling engine; not a code-side usage-factor calculator
  (caller wraps with CSR-mandated permissible ratios).

## What is not covered (v0.0.0)

- Stiffened-panel orthotropic buckling (CSR Section 8.4).
- Torsional / flexural-torsional buckling for thin-walled open
  sections (CSR Section 8.3, DNV RP-C201 Section 6).
- Biaxial / combined-loading interaction curves.
- Imperfection-sensitivity reductions.
- Web-shear post-buckling for plate girders.
- Code-specific usage factors.

## Composition

- Caller supplies plate / column section geometry derived from a yard
  midship section or stiffener-pattern definition.
- Composition with `yard-csr-zig` (UR S11 section-modulus check):
  buckling sets the permissible compressive flange stress;
  yard-csr-zig handles the global bending-moment side.
- For combined buckling + fatigue caller composes with
  `yard-csr-fatigue-zig` externally.
