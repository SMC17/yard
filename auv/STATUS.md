# Status

yard-auv-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2. 49/49 tests pass.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `hydrodynamics` | `unit-tested` | Schlichting + ITTC-57 C_F; drag ∝ V², S_w |
| `depth_control` | `unit-tested` | PD law clamp + steady-state ḋ = K_steady δ V |
| `endurance` | `unit-tested` | propulsion + hotel budget; optimal cruise closed form |
| `glider` | `unit-tested` | L/D glide angle + range per leg |

Evaluation logic `unit-tested`. Schlichting + form-factor + steady-
state-control + L/D-glider analytical formulas. Per-vessel
calibration of K_steady, K_d, eta_propulsive deferred.