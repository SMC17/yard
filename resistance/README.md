# yard-resistance-zig

Proof level: `unit-tested`

yard-resistance-zig is a Zig 0.16 implementation of the ITTC-57 friction
line and the Holtrop-Mennen 1984 reanalysis form factor plus
wave-resistance prediction, including the c17 / m3 high-Froude extension
and the 0.4 to 0.55 transition blend.

## What it does

- ITTC-57 friction coefficient `C_F = 0.075 / (log10(Rn) - 2)^2` for any
  Reynolds number above 1e5. Frictional resistance per unit wetted
  surface. Reynolds-number convenience function.
- Holtrop 1984 reanalysis form factor `(1 + k1)` using the single c14
  regression.
- Wave resistance `R_W` with three branches: low-Froude (Fn <= 0.4)
  using c1, m1, m4, lambda; high-Froude (Fn >= 0.55) using c17, m3,
  m4; and a linear blend in (10 Fn - 4) for the intermediate band.
- Half-angle of entrance `i_E` and the supporting auxiliary coefficients
  (c2, c5, c7, c15, c16, c17, m1, m3, m4, lambda) per Holtrop 1984.
- Total resistance `R_F (1+k) + R_W` with a typed breakdown struct.

## What it is not (v0.0.0)

This release covers friction, form factor, and wave resistance only.
The following components are deferred to v0.1.0:

- Bulb resistance (P_B, Fn_i, R_B).
- Immersed-transom resistance (Fn_T, c6, R_TR).
- Model-ship correlation allowance (c4, C_A, R_A).
- Appendage resistance (S_app, 1 + k2).
- Propulsion-factor chain (wake fraction w, thrust deduction t,
  relative rotative efficiency eta_R).

The c2 and c5 functions return 1.0 in this release (the case
A_BT = 0 and A_T = 0), so a hull with a bulb or immersed transom
needs the v0.1.0 release to be accurate.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 21/21 tests passed`.

## Bench

```
zig build bench -Doptimize=ReleaseFast
```

Sample numbers from a laptop with load average 5-64 during the run
(upper bounds, not best case):

```
ittc57.cF                        iters=200000    ns/call=   37.0
holtrop.formFactor1984           iters=200000    ns/call=   95.6
holtrop.totalResistance          iters=200000    ns/call= 1058.3
```

Total resistance is dominated by the wave-resistance branch evaluation
(both low-Fn and high-Fn computed, then blended or selected). The
`@exp` and `@cos` calls in `waveResistance` are not vectorized in
this v0.0.0 implementation.

## Public API

```zig
const yard = @import("yard_resistance");

// ITTC-57 friction coefficient.
const c_f = try yard.ittc57.cF(5.0e6);             // 0.003396

// Holtrop form factor + total resistance.
const hp: yard.holtrop.HullParticulars = .{
    .L = 100.0, .B = 16.0, .T = 6.0,
    .displacement_vol = 8500.0, .S = 2500.0,
    .C_B = 0.65, .C_M = 0.98, .C_P = 0.66, .C_WP = 0.78,
    .lcb_pct = -1.0, .c_stern = 0.0,
};
const env: yard.holtrop.Environment = .{};
const k = yard.holtrop.formFactor1984(hp);
const i_e = yard.holtrop.halfAngleOfEntrance(hp);
const r_w = yard.holtrop.waveResistance(hp, 8.0, env);
const br = try yard.holtrop.totalResistance(hp, 8.0, env);
// br.r_total, br.r_f, br.r_w, br.one_plus_k, br.c_f, br.rn, br.fn_val
```

## Coefficient verification posture

The c17 and m3 high-Froude formulas were transcribed from the codex
substrate Gap 2 closure at
`~/codex/sources/naome_data_substrate_deep.md`, which cross-verifies
them against two open implementations:

- FreeCAD-Ship Holtrop.py lines 163 to 180 (LGPL-2.1-or-later, J. L.
  Cercos-Pita, 2011, 2016).
- aletirelli/holtrop-mennen `HoltropMennen_FnOver04.py` line 51 to 52.

Both implementations cite Holtrop 1984 ISP 31 page 273 directly and
reproduce identical c17 and m3 formulas. The original ISP 31 paper is
paywalled at IOS Press and the TU Delft repository handle returns 403
for the data stream. Two-source open-implementation agreement is the
verification we have; absolute agreement with the original paper is
deferred until a clean copy of ISP 31 is obtained.

The c1, m1, m4, lambda, c14, c15, c16, c7 formulas are reproduced
from Holtrop 1982 / 1984 via the same codex substrate, cross-verified
against three independent Python implementations
(aletirelli/holtrop-mennen, KZABORSKI/PyMarine-UoS, rpipeau3d/Sim.B.A.D).

## Validity envelope

The PIAS Resist manual aggregate validity (per
`~/codex/sources/naome_data_substrate_deep.md` Section 2B):

| Parameter | Range |
|---|---|
| Fn | 0 to roughly 0.55+ (with the c17/m3 branch) |
| L/B | 3.9 to 14.9 |
| B/T | 2.1 to 4.0 |
| C_B | 0.55 to 0.85 |
| C_P | 0.55 to 0.85 |

The per-ship-type Table I from Holtrop 1984 ISP 31 is still blocked at
primary; the per-type envelope is unverified.

This v0.0.0 release does not enforce the envelope at runtime. The
caller is responsible for staying inside it. A future v0.x will add
an envelope-check function.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0). Strongest
available claim: `stable-on-zig-0.16-today`.

## References

- Holtrop, J. and Mennen, G.G.J. (1982). "An Approximate Power
  Prediction Method." International Shipbuilding Progress 29:335,
  pp 166+.
- Holtrop, J. (1984). "A Statistical Re-Analysis of Resistance and
  Propulsion Data." International Shipbuilding Progress 31:363,
  pp 272+.
- ITTC Recommended Procedure 7.5-02-03-01.4 (1978 Performance
  Prediction Method, current revision).
- Bertram, V. (2012). *Practical Ship Hydrodynamics*, 2nd ed.,
  Butterworth-Heinemann, Ch. 3.
- Codex cross-references at
  `~/codex/concepts/holtrop-mennen-resistance-prediction.md`,
  `~/codex/concepts/ittc-57-and-ittc-78-extrapolation.md`,
  `~/codex/sources/naome_data_substrate_deep.md` Section 2B.

## License

AGPL-3.0-or-later. See `LICENSE`.
