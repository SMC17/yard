# yard-cavitation-zig

Proof level: `unit-tested`

yard-cavitation-zig is a Zig 0.16 propeller-cavitation kernel. Two
modules: `burrill` for thrust-loading vs cavitation-number checks
against the 1943 Burrill chart at 5 % and 2.5 % back-cavitation
contours; `keller` for the minimum expanded blade-area ratio per
Keller 1973.

## What it does

### Burrill chart

- `burrill.velocityAt07RMPerS(V_a, n, D)` returns
  `V_R = sqrt(V_a^2 + (0.7 pi n D)^2)`.
- `burrill.localCavitationNumber(p0, pv, V_R, rho)` returns
  `(p_0 - p_v) / (0.5 rho V_R^2)`.
- `burrill.thrustLoadingCoefficient(T, V_R, A_P, rho)` returns
  `tau_c = T / (0.5 rho V_R^2 A_P)`.
- `burrill.permissibleTauC5Pct(sigma_n)` power-law fit
  `0.45 sigma_n^0.4` for the 5 % back-cavitation contour.
- `burrill.permissibleTauC2Pt5Pct(sigma_n)` `0.34 sigma_n^0.4`.
- `burrill.check5Pct(tau_c, sigma_n)` returns `.pass` or `.fail`.

### Keller blade-area ratio

- `keller.k_single_screw = 0.20`, `keller.k_twin_screw = 0.00`.
- `keller.minimumBladeAreaRatio(Z, T, p0, pv, D, K)` returns
  `(1.3 + 0.3 Z) T / ((p_0 - p_v) D^2) + K`.

## What it is not (v0.0.0)

- No tip-vortex / sheet-cavitation prediction (volume-fraction model).
- No erosion-rate prediction.
- No noise-spectrum (URN) coupling.
- No spatially varying inflow / wake field (uses 0.7 R representative
  velocity).
- No high-skew correction.
- No 3D cavity-shape solve (BEM/RANS coupling deferred).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 21/21 tests passed`.

## Public API

```zig
const yard = @import("yard_cavitation");

const V_R = try yard.burrill.velocityAt07RMPerS(5.0, 2.0, 6.0);
const sigma = try yard.burrill.localCavitationNumber(
    101_325.0 + 1025.0 * 9.81 * 5.0, 2300.0, V_R, 1025.0);
const tau_c = try yard.burrill.thrustLoadingCoefficient(
    1.2e6, V_R, 10.0, 1025.0);
const verdict = try yard.burrill.check5Pct(tau_c, sigma);

const ae_a0_min = try yard.keller.minimumBladeAreaRatio(
    4, 1.2e6, 1.5e5 + 2300.0, 2300.0, 6.0, yard.keller.k_single_screw);
```

## Validation

- V_R at zero advance reduces to `0.7 pi n D`.
- V_R combines advance and rotation in quadrature.
- sigma_n and tau_c closed forms to 1e-12.
- Burrill 5 % contour: tau_c_allow(sigma_n = 1) = 0.45;
  power-law sigma_n = 4 follows 0.45 * 4^0.4.
- Burrill 2.5 % contour: tau_c_allow(sigma_n = 1) = 0.34.
- check5Pct: low tau / high sigma passes; high tau / low sigma fails.
- Keller BAR at 4-blade single-screw merchant example (T=1.2 MN,
  D=6 m, p_0 - p_v = 1.5e5 Pa, K=0.20) yields 0.7556.
- Keller BAR scales linearly in T, inversely in D^2, monotonically
  with Z, and the K offset distinguishes single vs twin screw.
- Typed-error rejection for blade count outside [2,7], non-positive
  thrust, p_v >= p_0, non-positive area.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Burrill, L. C. (1943). *Calculation of Marine Propeller Performance
  Characteristics*. Trans. NECIES.
- Keller, J. auf'm. (1973). *Enige aspecten bij het ontwerpen van
  scheepsschroeven*. Schip en Werf 40.
- Carlton, J. (2018). *Marine Propellers and Propulsion*. 4th ed.,
  Butterworth-Heinemann.

## License

Apache-2.0.
