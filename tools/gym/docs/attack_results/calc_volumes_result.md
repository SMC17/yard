# HP Calc_Volumes hydrostatics — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Repo:** `/workspace/yard-sea-v0/`  
**Goal:** Wire Ship-D `Hull_Parameterization.Calc_Volumes` (via `Calc_VolumeProperties`) into Yard-Sea-v0 for on-demand / per-N-step hydrostatics beyond `project_to_hull`.

## What landed

| Piece | Path |
|-------|------|
| Wrapper API | `yard_sea_v0/shipd_surface.py` — `calc_volumes`, `VolumesReport`, `HydroStation`, `hull_from_volumes`, `clear_volumes_cache` |
| Env flag | `yard_sea_v0/env45.py` — `use_hp_hydro=True`, `hp_hydro_every_n` (0 = reset/info only), `hp_num_wl` / `hp_points_per_wl` |
| Tests | `tests/test_shipd_surface.py` (volumes + cache + drafts), `tests/test_env45.py` (reset + every-N) |
| Vendor | Silence `print(Z.shape)` in `gen_pointCloud` (README patch #3) |
| Status | `STATUS.md` item 7 marked done |

No GitHub push from this agent.

## API

```python
from yard_sea_v0.shipd import load_sample_vectors
from yard_sea_v0.shipd_surface import calc_volumes, hull_from_volumes

v = load_sample_vectors()[0]
# design draft (WL * Dd) by default
report = calc_volumes(v)
st = report.primary()
# st.displacement_t, st.lcb_m, st.vcb_m, st.awp_m2, st.lcf_m, st.ixx_m4, st.iyy_m4, ...

# optional multi-draft
report = calc_volumes(v, drafts=[0.3, 0.5, 0.628])

# refine HullState Cb / lcb_frac from surface volumes
hull = hull_from_volumes(v, report)
```

Upstream path: `Calc_VolumeProperties` → point cloud → `Calc_WaterPlaneArea` → **`Calc_Volumes`** → LCF / CB / 2nd moments / WSA / LWL. Wrapper interpolates curves at requested `drafts`.

**Coordinates:** `lcb_m` / `lcf_m` are HP x from bow; `lcb_frac = (LOA/2 - lcb_m) / LOA` (+fwd / −aft, HullState convention).

## Cost (documented)

Measured on this box, sample0, 2026-09-10 ET:

| Grid (`NUM_WL` / `PointsPerWL`) | Typical wall time | Notes |
|---------------------------------|-------------------|-------|
| **41 / 120 (default)** | **~25–30 ms** | Matches 101/1000 design-draft volume within ~0.05% |
| 101 / 1000 (upstream defaults) | ~0.5 s | Too heavy for every env step |

Optional **LRU cache** (64 entries) keys on rounded length-45 vector + grid; draft interpolation after a hit is free (`cached=True`, `elapsed_s=0`).

**Recommendation:** keep env default `use_hp_hydro=False` (cheap `project_to_hull`). Enable `use_hp_hydro=True` for reset/info; set `hp_hydro_every_n` (e.g. 5–10) if you want surface hydro during search without paying ~30 ms every step.

## Sample metrics (default 41/120, design draft)

| Sample | T (m) | V (m³) | Disp (t) | LCB (m) | VCB (m) | Awp (m²) | Cb (HP) | Cb (project) |
|--------|------:|-------:|---------:|--------:|--------:|---------:|--------:|-------------:|
| 0 | 0.628 | 6.822 | 6.993 | 4.868 | 0.340 | 12.925 | 0.617 | 0.894 |
| 1 | 0.264 | 1.531 | 1.569 | 4.613 | 0.157 | 8.487 | 0.446 | 0.900 |
| 3 | 0.070 | 0.058 | 0.059 | 5.142 | 0.050 | 1.590 | 0.029* | 0.894 |
| 9 | 0.174 | 0.816 | 0.836 | 5.124 | 0.104 | 6.523 | 0.386 | 0.892 |

\*Sample 3 has a very shallow WL; box-Cb on LOA×Bd×T is not meaningful — `hull_from_volumes` soft-clamps Cb into [0.35, 0.98].

HP surface Cb / LCB differ substantially from the algebraic `project_to_hull` guess — that is expected and is the point of this hook.

## env45 usage

```python
from yard_sea_v0.env45 import DesignSearchEnv45

env = DesignSearchEnv45(
    sample_index=0,
    use_hp_hydro=True,   # attach hp_hydro on reset; refine parent HullState
    hp_hydro_every_n=0,  # 0 = reset/info only; N>0 refresh every N steps
)
obs, info = env.reset()
info["hp_hydro"]["primary"]["displacement_t"]
```

When `hp_hydro_every_n > 0`, accepted steps with `step_count % N == 0` re-run `calc_volumes` and put `hp_hydro` in step `info`. Other steps keep cheap `project_to_hull` for L0/L1.

## Tests

```sh
cd /workspace/yard-sea-v0
.venv/bin/pytest tests/test_shipd_surface.py tests/test_env45.py -q
# full gym suite (exclude unrelated broken aero/vendor collectors):
.venv/bin/pytest tests/ -q --ignore=tests/test_aero_stubs.py
```

Observed: **16** focused passed; **69** under `tests/` with aero stubs ignored.

## Honesty / not claimed

- Not ITTC powering, not class society hydrostatics, not FAA/ops.
- Waterplane / volume integration is exploratory Ship-D surface math (point-cloud trapezoids).
- Default search path remains `project_to_hull` unless `use_hp_hydro` is opted in.
