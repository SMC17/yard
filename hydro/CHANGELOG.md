# Changelog

All notable changes documented here. Format roughly follows Keep-a-Changelog;
semver bound by `~/CONVENTIONS.md` C2 (pre-1.0 while Zig is pre-1.0).

## [0.0.0] 2026-05-29

Initial release. Foundation hydrostatic primitives for the yard naval
substrate. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `simpson.simpson13` composite Simpson's 1/3 rule on precomputed
  ordinate arrays (odd count, h > 0). Allocator-free.
- `simpson.simpson38` composite Simpson's 3/8 rule (count `3k+1`).
- `wigley.Hull` parametric Wigley parabolic hull with closed-form
  hydrostatic quantities: `volume`, `waterplaneArea`, `kb`, `lcb`,
  `iT`, `iL`, `bmT`, `bmL`, `kmT`, `kmL`, and form coefficients
  `cB = 4/9`, `cM = cP = cW = 2/3`. Plus `halfBreadth`,
  `waterlineOrdinates`, `sectionalAreas` for numerical work.
- `box_barge.Barge` rectangular barge with closed-form hydrostatic
  quantities; tested against Biran 2013 Ch.10 worked example.
- `integrate.volumeFromAreas` Simpson integration of sectional areas.
- `integrate.waterplaneAreaFromHalfBreadths` Simpson on waterline
  half-breadths with factor-of-two convention.
- `integrate.iTFromHalfBreadths` Simpson integration of `(2/3) y^3`.
- `integrate.lcbFromAreas` first-moment integration with caller-supplied
  scratch buffer.
- 28-test unit suite validating numerical integration against
  closed-form rational values plus a convergence-rate test for
  the non-exact I_T integrand.
- `zig build bench -Doptimize=ReleaseFast` step measuring Simpson 1/3
  latency on Wigley waterlines at N = 11 through 321 stations.

### Validation

Closed-form derivations cross-checked against
`~/codex/concepts/simpsons-rule-for-naval-architecture.md`,
`~/codex/concepts/bonjean-curves.md`,
`~/codex/sources/validation_fixtures.md`, and
`~/codex/sources/hulls/wigley/parametric.md`.

### Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16. Cannot claim v1.0 in
semver spirit while Zig is pre-1.0. Strongest available claim:
`stable-on-zig-0.16-today`.

### Bench environment

Numbers in README reflect a laptop with background load average 12-64
during measurement (NOT a clean machine). Numbers are upper bounds on
single-thread Simpson 1/3 latency, not best-case.
