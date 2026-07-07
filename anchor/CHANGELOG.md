# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `holding.AnchorType` enum, `kFactor` (1.0 / 1.3 / 1.7).
- `holding.anchorHoldingKN` Stevin K W^0.92.
- `holding.chainSeabedHoldingKN` mu w L.
- `holding.totalHoldingKN` composer.
- `scope.recommended_scope_moderate`, `recommended_scope_storm`.
- `scope.minimumCableLengthM`, `scopeRatio`.
- `scope.scopeVerdict` acceptable / insufficient at 5:1 boundary.
- 19-test unit suite including W^0.92 scaling, anchor-type ratios,
  chain linearity, 210/300 m worked examples, and typed-error
  rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Caveats

K-factor table flagged `claimed`; supplier-specific anchor data
may differ within nominal class.
