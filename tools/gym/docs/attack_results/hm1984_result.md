# Holtrop HM1984 Zig L1 teacher — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Goal:** Wire vendored yard Holtrop HM1984 Zig as L1 teacher for Yard-Sea-v0.

## Success criteria

| Criterion | Status |
|-----------|--------|
| Resistance module in zig_gym build | **PASS** — `yard_resistance` package → `../vendor/yard_zig/resistance/src/root.zig` |
| Full HM1984 callable from CLI JSON | **PASS** — modes `l1_hm1984` / `both_hm1984` / alias `hm1984` |
| HullState → HullParticulars mapping | **PASS** — best-effort; missing fields documented |
| `zig_bridge` fidelity API | **PASS** — `estimate_resistance_zig(..., fidelity='simplified'\|'hm1984')` |
| Prefer Zig HM1984 teacher path | **PASS** — `teachers/zig_l1.py`; `resistance_l1.estimate_resistance(prefer_zig_hm1984=True)` |
| Tests: finite Ct; skip/xfail if build fails | **PASS** — `tests/test_hm1984.py` (4) + existing bridge parity (5) |
| No GitHub push | **PASS** |

## Default hull spot check (L=120, B=20, T=8, Cb=0.75, Fn=0.20)

| Path | Ct | Rt_N | fidelity |
|------|-----|------|----------|
| Python simplified | ~0.00251059 | ~255106 | L1_holtrop_simplified |
| Zig simplified | ~0.00251059 | ~255106 | L1_holtrop_simplified |
| Zig HM1984 | ~0.00259060 | ~263236 | L1_holtrop_hm1984 |

Parity **not** required between simplified and HM1984 (different Cp/Cm/Cwp/c_stern and full wave branch).

## Mapping notes (missing HullState fields)

| Holtrop field | Fill |
|---------------|------|
| C_M | default **0.98** |
| C_P | C_B / C_M (clamped) |
| C_WP | Denny `(1 + 2 C_B) / 3` |
| c_stern | **0** (normal); simplified used ≈10 |
| bulb / transom | null (no R_B / c₅) |

Present: L, B, T, C_B←Cb, S←wetted_approx, displacement_vol←volume, lcb_pct←lcb_frac×100.

## Artifacts

- `zig_gym/build.zig` — imports `yard_resistance`
- `zig_gym/root.zig` — `toHoltropParticulars`, `estimate_resistance_hm1984`
- `zig_gym/main.zig` — CLI modes for HM1984
- `yard_sea_v0/zig_bridge.py` — fidelity kwarg
- `yard_sea_v0/teachers/zig_l1.py` — teacher prefer-HM1984
- `yard_sea_v0/resistance_l1.py` — optional `prefer_zig_hm1984`
- `tests/test_hm1984.py`
- `vendor/yard_zig/INTEGRATION.md` — updated

## Limits / next

- Hydro `box_barge` GM not yet preferred for Cb≈1 (L0 still Python-parity gm0).
- No C ABI / shared lib yet; subprocess JSON remains primary.
- High-Cb exploratory hulls may sit outside Holtrop validity envelope; teacher still returns a finite estimate.
- Do not claim ITTC powering / class society grade.
