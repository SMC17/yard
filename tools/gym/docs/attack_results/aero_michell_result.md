# Strip aero oracles + Michell L1.5 — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Goal:** Scaffold Strip-path aero oracles (OpenVSP, NeuralFoil, JSBSim) and Michell wave-drag L1.5 for Yard-Sea-v0 ↔ Strip bridge.  
**Honesty:** not cert · not operational · not ITTC powering · not FAA/class

## Success criteria

| Criterion | Status |
|-----------|--------|
| Michell wrap `ModifiedMichellCw` → `teachers/michell_l15.py` | **PASS** — Wigley offsets from `HullState`; fidelity `L1.5_michell` |
| Michell tests + optional CLI `--l15-michell` | **PASS** |
| `openvsp_stub` / `neuralfoil_stub` / `jsbsim_stub` detect()/run() | **PASS** |
| Skip cleanly when absent; install hints | **PASS** |
| Shared teacher protocol in `teachers/__init__.py` | **PASS** |
| `docs/STRIP_ORACLES.md` linking assurance gates | **PASS** |
| NeuralFoil pip + real thin call | **PASS** — `neuralfoil==0.3.3` |
| JSBSim pip + real thin call | **PASS** — `jsbsim==1.3.1` (`c172x`) |
| OpenVSP light install | **SKIP** — no apt/pip package; stub skips `openvsp_unavailable` |
| pytest green | **PASS** — **68 passed** |

## Spot checks (this box)

| Teacher | Result |
|---------|--------|
| Michell default hull Fn=0.2 | Cw≈3.32e-4, Rw≈1.15e5 N, Ct≈8.01e-4, `skipped=False` |
| NeuralFoil NACA0012 α=2° Re=1e6 `small` | CL≈0.219, CD≈0.00616 |
| JSBSim `c172x` 5 steps | sim_time≈0.042 s, Vt≈171 fps |
| OpenVSP | unavailable → skip |

## Artifacts

- `yard_sea_v0/teachers/michell_l15.py`
- `yard_sea_v0/teachers/openvsp_stub.py`
- `yard_sea_v0/teachers/neuralfoil_stub.py`
- `yard_sea_v0/teachers/jsbsim_stub.py`
- `yard_sea_v0/teachers/__init__.py` — protocol docstring
- `docs/STRIP_ORACLES.md`
- `tests/test_michell_l15.py`, `tests/test_aero_stubs.py`
- CLI/gallery: `--l15-michell`
- `strip_assurance` validation_gates: `michell_l15`, `aero_oracle` (default False)

## How to exercise

```sh
cd /workspace/yard-sea-v0
source .venv/bin/activate
pip install neuralfoil jsbsim   # optional Strip aero
PYTHONPATH=. pytest -q tests/test_michell_l15.py tests/test_aero_stubs.py
PYTHONPATH=. python -m yard_sea_v0 run-search --parents 1 --steps 2 --l15-michell --out out/michell_gallery
```

## Hard stops / deferred

- OpenVSP binary / VSPAERO adapter not on box (stub only)
- Michell uses **synthetic Wigley** offsets — not full Ship-D waterline mesh export yet
- Aero oracles do not raise Strip `assurance_level` beyond L1_rank
- No GitHub push

