# Changelog

Format roughly follows Keep-a-Changelog. Semver bound by
`~/CONVENTIONS.md` C2 (pre-1.0 while Zig is pre-1.0).

## [0.0.0] 2026-05-29

Initial release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `wageningen.kT` K_T polynomial evaluator. 39 terms, Oosterveld 1975
  Table 5 left column.
- `wageningen.kQ` K_Q polynomial evaluator. 47 terms, Table 5 right
  column.
- `wageningen.etaO` open-water propulsive efficiency.
- `wageningen.deltaKT` and `wageningen.deltaKQ` Reynolds correction
  polynomials (Oosterveld 1975 Table 6).
- `wageningen.validate` envelope checker for Z, P/D, A_E/A_0, J, Rn
  with explicit error variants per parameter.
- 20-test unit suite covering sign behavior, monotonicity,
  P/D-effect qualitative checks, peak-efficiency bound, parameter
  validity rejection, Reynolds-correction magnitude, term-count
  assertion, regression locks at known operating points.
- `zig build bench -Doptimize=ReleaseFast` measuring per-call
  latency of K_T and K_Q on a B4-70 P/D=1.0 trace.

### Coefficient verification posture

Coefficients transcribed from the codex substrate at
`~/codex/sources/naome_data_substrate_deep.md` Section 2A. Eleven
rows were OCR-ambiguous on the source scan; values used are the
canonical ones downstream implementations carry. Cross-check against
a clean Bernitsas 1981 print or against FreeCAD-Ship or NSMB-MARIN
implementations is deferred. See `STATUS.md` for the explicit row list.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.

### Bench environment

Numbers in README reflect a laptop with load average 242 during
measurement. Upper bounds, not best-case.

## [0.1.0] 2026-05-30

Deepening release. Pre-1.0; stable-on-zig-0.16-today.

### Added

- `openwater` module: open-water efficiency eta_0 = J/(2 pi) K_T / K_Q;
  three-point quadratic K_T(J) / K_Q(J) fit; ITTC-78 Lerbs Reynolds
  correction (delta_K_T, delta_K_Q) and Lerbs friction C_D
  closed form; Holtrop-Mennen eta_R for single-screw and twin-screw
  configurations; peakEfficiencyJ brute-force search in (J_lo, J_hi).
- 14 unit tests including eta_0 closed form, parabolic recovery,
  Lerbs C_D Re-decay, eta_R typical-range guards, and peak search.

### Constraint inheritance

Bound by Zig 0.16 (pre-1.0) per `~/CONVENTIONS.md` C2.
