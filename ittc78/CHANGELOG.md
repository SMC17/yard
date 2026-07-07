# Changelog

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `chain.ModelScale`, `chain.ShipScale`, `chain.PropulsionFactors`,
  `chain.Propeller` typed input structs.
- `chain.extrapolate` 11-step ITTC-78 chain producing a typed
  `chain.Result` with all intermediate quantities (Reynolds at both
  scales, C_F at both, C_R, C_A, C_AA, C_T_ship, R_T_ship, P_E,
  P_D, P_S).
- 12-test unit suite covering Reynolds match, C_R derivation, C_A
  formula, P_S / P_D / eta_S relation, V^3 scaling, and input
  validation.
- Bench step measuring full-chain latency.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
