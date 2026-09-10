# CadQuery / OCCT mesh export — RESULT

**Date:** 2026-09-10 (America/New_York)  
**Venv:** `/workspace/yard-sea-v0/.venv` (Python 3.13.5)  
**Outcome:** **SUCCESS — CadQuery path works** (non-box soft-chine loft). Pure-Python tapered prism kept as fallback.

## 1. Install

| Package | Version | Notes |
|---------|---------|-------|
| `cadquery-vtk` | 9.3.1 | Installed first (Py3.13 VTK band-aid) |
| `cadquery` | 2.8.0 | pip — **not conda-only** |
| `cadquery-ocp` | 7.9.3.1.1 | OCCT wheels for cp313 manylinux |
| `vtk` | 9.6.2 | Pulled by cadquery-ocp |

Commands used:

```sh
.venv/bin/pip install --upgrade pip
.venv/bin/pip install cadquery-vtk
.venv/bin/pip install cadquery
```

**Blocker avoided:** Older docs imply conda for OCP; current manylinux wheels + `cadquery-vtk` install cleanly on this box. No conda required.

## 2. Implementation (`yard_sea_v0/mesh.py`)

- `write_box_stl` — legacy 12-facet box (unchanged semantics).
- `try_cadquery_chine` — **real** soft-chine loft (YZ station polygons → OCCT loft), planform from `taper_fractions(Cb, lcb)` or explicit Ship-D `Lb`/`Ls`.
- `write_tapered_prism_stl` — same planform/sections without CadQuery (~400 facets vs 12).
- `export_hull_stl` — prefers CadQuery, else tapered prism, else box; returns `(path, backend)`.
- `try_shipd_principals_loft` — CadQuery loft with Ship-D Lb/Ls (not full 45-D `Hull_Parameterization` surface).

Gallery now calls `export_hull_stl` instead of box-only.

**Not claimed:** Full Ship-D NURBS/waterline mesh, 49-constraint mesh validity, ITTC/class fidelity. Upstream HP STL remains a separate track (`vendor/shipd_upstream`).

## 3. Sample STLs (`out/`)

| File | Bytes | Backend |
|------|------:|---------|
| `sample_box.stl` | 3094 | box |
| `sample_tapered_prism.stl` | 51577 | tapered_prism |
| `sample_cadquery_chine.stl` | 36884 | cadquery_chine |
| `sample_export_auto.stl` | 36884 | cadquery_chine (auto) |
| `sample_shipd_principals.stl` | 20484 | cadquery_chine + sample Lb/Ls |

## 4. Tests

```sh
PYTHONPATH=. .venv/bin/pytest -q tests/test_mesh.py
# 7 passed
```

Coverage: box write, taper fractions, station beam, tapered richer than box, export non-box, CadQuery when available, Ship-D Lb/Ls path.

## 5. Honest residual gaps

1. Soft-chine loft ≈ exploratory geometry from principals — **not** Ship-D surface equations.
2. Longitudinal `|X` fillet often no-ops on lofted edges (OCCT selection); shape still non-box via lofted chines.
3. Volume of solid ≠ `L*B*T*Cb` hydrostatic model (mesh is visual/export; hydro stays on `HullState`).

## 6. Repro

```sh
cd /workspace/yard-sea-v0
.venv/bin/pip install cadquery-vtk cadquery   # if needed
PYTHONPATH=. .venv/bin/python -c "
from pathlib import Path
from yard_sea_v0.hull import HullState
from yard_sea_v0.mesh import export_hull_stl
p, tag = export_hull_stl(HullState(), Path('out/demo.stl'))
print(tag, p, p.stat().st_size)
"
```
