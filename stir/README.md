# yard-stir-zig

Proof level: `unit-tested`

yard-stir-zig is a Zig 0.16 IMO Second-Generation Intact Stability
(STIR) Vulnerability Level 1 kernel per MEPC.1/Circ.1627. Two modules:
`dead_ship` implements the dead-ship-condition VL1 check based on the
residual roll envelope `phi_1 = phi_0 + 1.7 phi_m`; `parametric`
implements the parametric-roll VL1 check based on the principal
Mathieu-resonance ratio `R = omega_e / (2 omega_phi)`.

## What it does

### Dead-ship VL1

- `dead_ship.staticHeelAngleSmallAngleRad(M_wind, Delta, GM, g)` small-
  angle steady wind-heel `phi_0 = M_wind / (Delta GM g)`.
- `dead_ship.residualRollAngleRad(phi_0, phi_m)` returns the VL1
  envelope `phi_0 + 1.7 phi_m`.
- `dead_ship.verdict(phi_1, phi_F)` pass / fail vs deck-edge or
  downflooding angle.

### Parametric-roll VL1

- `parametric.encounterFrequencyRps(omega_w, k, V, mu)` returns
  `omega_w - k V cos mu`.
- `parametric.naturalRollFrequencyRps(GM, k_xx, g)` returns
  `sqrt(g GM) / k_xx`.
- `parametric.principalMathieuRatio(omega_e, omega_phi)` returns
  `omega_e / (2 omega_phi)`.
- `parametric.verdict(R)` fails if `R in [0.85, 1.15]`.

## What it is not (v0.0.0)

- No VL2 (probabilistic) check (caller composes externally).
- No direct-time-domain simulation gate.
- No surf-riding / broaching VL1 (Melnikov-style criterion deferred).
- No excessive-acceleration / pure-loss-of-stability VL1.
- No multi-degree-of-freedom roll-pitch-heave coupling (compose with
  `yard-coupled-motions-zig`).
- No nonlinear GZ curve crossing (linear small-angle only).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 20/20 tests passed`.

## Public API

```zig
const yard = @import("yard_stir");

// Dead-ship VL1.
const phi_0 = try yard.dead_ship.staticHeelAngleSmallAngleRad(
    1.0e6, 10_000_000.0, 1.2, 9.81);
const phi_1 = try yard.dead_ship.residualRollAngleRad(phi_0, 0.35);
const v_ds = yard.dead_ship.verdict(phi_1, 40.0 * std.math.pi / 180.0);

// Parametric-roll VL1.
const omega_e = try yard.parametric.encounterFrequencyRps(
    0.7, 0.05, 9.0, std.math.pi);  // head seas
const omega_phi = try yard.parametric.naturalRollFrequencyRps(
    1.2, 12.0, 9.81);
const R = yard.parametric.principalMathieuRatio(omega_e, omega_phi);
const v_pr = yard.parametric.verdict(R);
```

## Validation

- Static heel scales linearly with wind moment and inversely with GM.
- Residual roll formula `phi_1 = phi_0 + 1.7 phi_m` closed form.
- Verdict pass at `phi_1 < phi_F`; fail at `phi_1 >= phi_F`.
- Encounter frequency: head seas (mu = pi) maximises omega_e; mu = 0
  minimises.
- Natural roll frequency `sqrt(g GM) / k_xx` closed form.
- 2:1 Mathieu resonance gives R = 1.0.
- Verdict R = 0.85 fails (band edge); R = 0.50 and R = 1.20 pass.
- Typed-error rejection for negative moment, non-positive GM / k_xx
  / V, negative phi_m.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- IMO MEPC.1/Circ.1627. *Interim Guidelines on the Second Generation
  Intact Stability Criteria*.
- Belenky, V., Bassler, C. C., Spyrou, K. J. (2011). *Development of
  Second Generation Intact Stability Criteria*. NSWCCD-50-TR-2011/065.
- France, W. N., Levadou, M., Treakle, T. W., Paulling, J. R.,
  Michel, R. K., Moore, C. (2003). *An Investigation of Head-Sea
  Parametric Rolling and its Influence on Container Lashing Systems*.
  Marine Technology 40.

## License

AGPL-3.0-or-later.
