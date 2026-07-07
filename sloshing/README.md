# yard-sloshing-zig

Proof level: `unit-tested`

yard-sloshing-zig is a Zig 0.16 linear-potential-flow sloshing kernel
for rectangular liquid-cargo tanks per Faltinsen and Timokha (2009).
The eigenfrequencies of the free surface satisfy
`omega_n^2 = g k_n tanh(k_n h)` with antisymmetric wave numbers
`k_n = (2n + 1) pi / L` (the modes excited by horizontal sway) and
symmetric wave numbers `k_n = 2 n pi / L` (excited by heave / surge).

## What it does

- `rectangular.waveNumberAntisymmetric(n, L)` returns the
  antisymmetric horizontal-mode wave number.
- `rectangular.waveNumberSymmetric(n, L)` returns the symmetric
  vertical-mode wave number for `n >= 1`.
- `rectangular.naturalAngularFrequency(k, h, g)` evaluates
  `omega = sqrt(g k tanh(k h))`.
- `rectangular.naturalPeriodSec(omega)` returns `T = 2 pi / omega`.
- `rectangular.fundamentalAntisymmetricRectangular(L, h, g)`
  convenience wrapper for the dominant resonance (n = 0).
- `rectangular.deepWaterLimitOmega(k, g)` returns `sqrt(g k)`.
- `rectangular.shallowWaterLimitOmega(k, h, g)` returns
  `k sqrt(g h)`.

## What it is not (v0.0.0)

- No nonlinear modal (multimodal) analysis (compose externally).
- No prismatic / membrane LNG-tank shape (Faltinsen-Timokha
  multimodal needed for chamfered geometry).
- No impact-pressure prediction (Smith / DNV-RP-C205).
- No coupled-tank-vessel-motion solver (compose with
  `yard-coupled-motions-zig`).
- No viscous damping correction.
- No two-layer / stratified sloshing.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 12/12 tests passed`.

## Public API

```zig
const yard = @import("yard_sloshing");

// Dominant resonance for an L = 30 m, h = 12 m rectangular tank.
const omega_1 = try yard.rectangular.fundamentalAntisymmetricRectangular(
    30.0, 12.0, 9.81);
const T_1 = yard.rectangular.naturalPeriodSec(omega_1);

// Higher-mode breakdown.
const k_2 = try yard.rectangular.waveNumberAntisymmetric(1, 30.0);
const omega_2 = try yard.rectangular.naturalAngularFrequency(k_2, 12.0, 9.81);
```

## Validation

- Antisymmetric wave numbers `k_0 = pi/L`, `k_1 = 3 pi / L`.
- Symmetric wave numbers `k_1 = 2 pi / L`, `k_2 = 4 pi / L`.
- Fundamental closed form reproduces
  `sqrt(g (pi/L) tanh(pi h / L))` to 1e-12.
- Deep-water limit `omega -> sqrt(g k)` as `k h -> infinity`.
- Shallow-water limit `omega -> k sqrt(g h)` as `k h -> 0`.
- Higher modes have higher frequencies (monotone).
- Faltinsen-Timokha (2009) Section 4.3.1 worked example
  L = 1.73 m, h = 0.6 m, g = 9.81 yields omega_1 ~ 3.768 rad/s.
- Typed-error rejection for non-positive length / depth / gravity
  and symmetric mode index n = 0.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Faltinsen, O. M., Timokha, A. N. (2009). *Sloshing*. Cambridge.
- Abramson, H. N. (1966). *The Dynamic Behavior of Liquids in
  Moving Containers*. NASA SP-106.
- Ibrahim, R. A. (2005). *Liquid Sloshing Dynamics: Theory and
  Applications*. Cambridge.

## License

Apache-2.0.
