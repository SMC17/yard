# Changelog

## [0.0.0] 2026-05-30

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `cpm.Activity`, `cpm.Edge` typed structs.
- `cpm.forwardPass`, `projectFinish`, `backwardPass`, `totalFloat`.
- `pert.Triple` typed struct.
- `pert.mean`, `standardDeviation`, `variance`, `projectMean`,
  `projectVariance`, `zScore`.
- `resource.ResourceWindow` typed struct.
- `resource.buildHistogram`, `peakLoad`, `averageLoad`,
  `totalResourceDays`, `smoothnessRatio`.
- 32-test unit suite including single-activity / linear chain /
  diamond network forward + backward pass + float, PERT mean /
  sigma / variance / Z-score, resource histogram + peak / average /
  total / smoothness, and typed-error rejection.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
