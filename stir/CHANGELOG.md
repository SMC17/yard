# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `dead_ship.staticHeelAngleSmallAngleRad` small-angle wind heel.
- `dead_ship.residualRollAngleRad` phi_0 + 1.7 phi_m envelope.
- `dead_ship.verdict` pass / fail against deck-edge / downflooding.
- `parametric.encounterFrequencyRps` omega_w - k V cos mu.
- `parametric.naturalRollFrequencyRps` sqrt(g GM) / k_xx.
- `parametric.principalMathieuRatio` omega_e / (2 omega_phi).
- `parametric.verdict` band [0.85, 1.15] failure region.
- 20-test unit suite including closed-form scaling, head / following
  seas limits, 2:1 resonance, and band-edge inclusion.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
