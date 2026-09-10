# Zig HM1984 default L1 teacher — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Goal:** Make Zig HM1984 the default L1 resistance teacher in Yard-Sea-v0 whenever `yard_sea_zig` is present; Python Holtrop-simplified becomes fallback.

## Success criteria

| Criterion | Status |
|-----------|--------|
| `resistance_l1.estimate_resistance` defaults `prefer_zig_hm1984=True` | **PASS** |
| Zig path used when binary works (`hm1984_zig`) | **PASS** |
| Python Holtrop-simplified fallback (`simplified_py`) | **PASS** — missing binary or Zig raise |
| Env / search / gallery pick up automatically | **PASS** — all call `estimate_resistance` without override |
| Evidence packs note fidelity | **PASS** — `resistance.fidelity` + claim `fidelity` / statement |
| Tests: default path + fallback | **PASS** — `tests/test_zig_default_l1.py` (5) + updated hm1984/bridge |
| Branch + PR | see push section |

## Default hull spot check (L=120, B=20, T=8, Cb=0.75, Fn=0.20)

| Path | Ct | fidelity |
|------|-----|----------|
| **Default** (`estimate_resistance(h)`) | ~0.00259060 | **hm1984_zig** |
| Forced Python (`prefer_zig_hm1984=False`) | ~0.00251059 | **simplified_py** |

## Behavior

1. `estimate_resistance(h)` → try Zig HM1984 if `zig_available()`; on success return `fidelity="hm1984_zig"`.
2. If binary missing or Zig raises → Python Holtrop-simplified with `fidelity="simplified_py"`.
3. Env step `info["l1_fidelity"]`, search `ChildResult.l1_fidelity`, gallery `parents[].l1_fidelity` / `l1_fidelity_default`.
4. Evidence claim `drag_rank_l1` cites `hm1984_zig` or `simplified_py`.
5. Env override: `YARD_SEA_PREFER_ZIG_HM1984=0` still respected by `teachers.zig_l1`; force Python via `prefer_zig_hm1984=False`.

## Tests

```
pytest -q tests/test_zig_default_l1.py tests/test_hm1984.py tests/test_zig_bridge.py
# + related suite: 54 passed (botorch/corpus/michell/multifidelity/openfoam/zig*)
```

## Artifacts

- `yard_sea_v0/resistance_l1.py` — default prefer Zig
- `yard_sea_v0/zig_bridge.py` — normalize to `hm1984_zig`; alt binary paths
- `yard_sea_v0/evidence.py` — claim fidelity note
- `yard_sea_v0/{env,search,gallery}.py` — surface `l1_fidelity`
- `yard_sea_v0/teachers/zig_l1.py` — fallback forces Python
- `zig_gym/main.zig` — CLI emits `hm1984_zig`
- `tests/test_zig_default_l1.py`

## Limits

- Not ITTC powering / not class-society grade.
- High-Cb exploratory hulls may sit outside Holtrop validity envelope.
- Parity tests must pass `prefer_zig_hm1984=False` (simplified Python ↔ Zig simplified).
