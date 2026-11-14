# L2 panel/BEM teacher (Capytaine) — RESULT

**Date:** 2026-09-10 19:00 EDT  
**Goal:** Scaffold an L2 panel/BEM teacher between Michell L1.5 and OpenFOAM L3 for Yard-Sea-v0.  
**Honesty:** **not ITTC powering · not class · not model-test validated · exploratory ranking only**

## Success criteria

| Criterion | Status |
|-----------|--------|
| Research pip-installable panel/BEM on this box | **PASS** — `capytaine==3.0.0` + `meshio`; meshmagick **not** on PyPI; HydroGym/FluidGym are RL CFD envs (not ship panel) |
| `teachers/panel_l2.py` with `detect()` / `run()` → Cw/Cd-like; skip if deps missing | **PASS** |
| Real thin Capytaine call on simple geometry | **PASS** — parallelepiped radiation Surge + diffraction |
| Optional STL / Ship-D offsets path | **PASS** — `stl_path=` via `load_mesh` + immersed shift |
| Wire `--l2-panel` into gallery (+ multifidelity `use_l2` when present) | **PASS** (gallery/CLI on PR; local box also has `multifidelity.attach_l2`) |
| Tests | **PASS** — `tests/test_panel_l2.py` **7 passed** |
| RESULT markdown | **PASS** — this file |
| Push `feat/yard-sea-panel-l2` + PR | **PASS** — https://github.com/SMC17/yard/pull/7 |

## Research notes

| Package | pip? | Role |
|---------|------|------|
| **capytaine** 3.0.0 | yes | Linear potential-flow BEM (radiation / diffraction) |
| meshio | yes | STL load path used by Capytaine |
| meshmagick | **no** matching PyPI dist on this box | skipped |
| HydroGym / FluidGym | yes but wrong tool | RL / CFD control envs — not a calm-water panel teacher |

## API

```python
from yard_sea_v0.teachers.panel_l2 import detect, run
from yard_sea_v0.hull import HullState

print(detect().to_dict())
r = run(HullState(L=20, B=4, T=2, Fn=0.20), resolution=(10, 4, 4))
# r["fidelity"] == "L2_panel_bem"
# r["Cw"], r["Cd"] / r["Cd_like"], r["Cw_like"]  — ranking proxies
# r["backend"] == "capytaine"
```

Skip path (no Capytaine):

```python
r = run(h, availability=PanelAvailability(capytaine=False))
# skipped=True, skip_reason="capytaine_missing", fidelity="L2_pending"
```

CLI:

```sh
pip install 'capytaine>=2.2'   # optional
python -m yard_sea_v0 run-search --l2-panel --parents 1 --steps 2 --out out/l2_gallery
# also works with --multifidelity --l2-panel (Stage-A attach_l2 before elite L3)
```

## Spot checks (this box, Capytaine 3.0.0)

| Geometry | faces | Cw | Cd_like | fidelity |
|----------|------:|---:|--------:|----------|
| Parallelepiped L=20 B=4 T=2 Fn=0.20 | 192 | 4.12e-2 | 2.19 | `L2_panel_bem` |
| Ship-D sample[0] STL (immersed) | 1290 | 7.08e-3 | 2.87 | `L2_panel_bem` |

**Interpretation (honest):** Capytaine is frequency-domain linear BEM, **not** steady wave-resistance.  
`Cd_like` = \|F_surge\| / (½ρU²·B·T) from diffraction; `Cw_like` / `Cw` from radiation damping Surge.  
Magnitudes are ranking proxies only — do **not** compare to Michell Cw or ITTC Ct as physical equals.

## Files touched

- `yard_sea_v0/teachers/panel_l2.py` (new)
- `yard_sea_v0/teachers/__init__.py` — fidelity ladder + export
- `yard_sea_v0/gallery.py` — `--l2-panel` summaries / STL handoff
- `yard_sea_v0/cli.py` — `--l2-panel`
- `yard_sea_v0/multifidelity.py` — `COST_L2`, `attach_l2`, `use_l2`
- `tests/test_panel_l2.py` (new)
- `requirements.txt` / `README.md` / `STATUS.md` comments

## Tests

```sh
cd tools/gym   # or /workspace/yard-sea-v0
source .venv/bin/activate
PYTHONPATH=. pytest -q tests/test_panel_l2.py
# 7 passed
```

## Hard stops / deferred

- Not a Rankine steady wave-drag solver (Capytaine is the closest public pip BEM)
- Default gallery L2 uses child STL when present, else parallelepiped from HullState
- Cd_like can be O(1)–O(10) on box geometries — expected for this proxy, not a bug
- Still **not** ITTC / not class / not operational

## Artifacts

- `docs/attack_results/panel_l2_result.md` (this file)
- `yard_sea_v0/teachers/panel_l2.py`
- `tests/test_panel_l2.py`
