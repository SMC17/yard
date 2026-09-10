# OpenFOAM forceCoeffs — Yard-Sea-v0 L3 teacher

**Date:** 2026-09-10 ~5:40 PM ET (America/New_York)  
**Outcome:** **SUCCESS** — snappyHexMesh hull patch + real `forceCoeffs` / `coefficient.dat` → teacher fidelity **`L3_rans`**.

## Goal

Go beyond potentialFoam-only empty-box smoke: snap a hull STL, run checkMesh + solver, parse Cd, map into the L3 teacher with an honest fidelity label.

## Environment

| Piece | Status |
|---|---|
| Debian OpenFOAM 1912 (`/usr/bin/{blockMesh,snappyHexMesh,checkMesh,potentialFoam,simpleFoam}`) | installed; needs `FOAM_ETC=/usr/share/openfoam/etc` |
| Docker `opencfd/openfoam-default:2412` | pulled; dockerd via `sudo dockerd … &` when needed |
| Disk | ~102G free (skip if &lt;1G) |
| Native `libforces` / forceCoeffs | **broken** on this host (OpenSSL 3 → `IOstream "sha1"` FATAL) |

## Pipeline (hybrid)

1. **`prepare_case`** — copy `cases/openfoam_hull_v0/`, inject STL, size `blockMesh` from STL bbox, set freestream + `forceCoeffs1` placeholders, write `system/forceCoeffs1`.
2. **Native mesh** — `blockMesh` → `snappyHexMesh -overwrite` (castellated+snap, level 1) → `checkMesh` → optional `potentialFoam -writep` (no functionObjects).
3. **Docker solve** — short laminar `simpleFoam` (`endTime=3`) in OpenFOAM-2412 writes `postProcessing/forceCoeffs1/0/coefficient.dat`.
4. **Parse** — `parse_force_coeffs` / `find_force_coeffs` (supports `forceCoeffs.dat` and 2412 `coefficient.dat`).
5. **Map** — Cd → Ct proxy; fidelity **`L3_rans`** (simpleFoam) or **`L3_potential`** if a potential-only FO path ever works. Skip → **`L3_pending`** on timeout / disk / snappy / sha1 / missing FO.

## Smoke results

### Tapered-prism hull (`out/sample_tapered_prism.stl`, L=120 B=20 T=8, Fn=0.2)

| Step | Result |
|---|---|
| snappyHexMesh | Mesh OK, **hull** patch ~312 faces, ~4.3k cells |
| checkMesh | Mesh OK |
| simpleFoam (Docker 2412) | End after 3 iters |
| Cd (last) | **0.1459** |
| Cl / CmPitch | -0.175 / 0.0494 |
| Teacher | `skipped=False`, **`fidelity=L3_rans`**, `solver=simpleFoam` |
| Wall time | ~20 s |

Case: `out/forcecoeffs_smoke/teacher_case_v2/`

### Ship-D surface STL (`out/shipd_surface/sample3_nobulb.stl`, ~10 m LOA)

| Field | Value |
|---|---|
| Cd | **0.2898** |
| fidelity | **L3_rans** |
| Wall time | ~20 s |

Case: `out/forcecoeffs_smoke/shipd_case/`

## Code / case changes

- `cases/openfoam_hull_v0/` — bbox-driven `blockMeshDict`, coarse `snappyHexMeshDict` + `meshQualityDict`, `forceCoeffs` in `controlDict`, laminar-ready `fvSchemes`/`fvSolution`, short `endTime`, updated `Allrun`.
- `yard_sea_v0/teachers/openfoam_l3.py` — STL bbox, domain sizing, hybrid mesh/solve, `L3_potential` / `L3_rans` / `L3_pending`, disk/timeout skip, Docker forceCoeffs path around Debian sha1 bug.
- `tests/test_openfoam_l3.py` + `tests/fixtures/forceCoeffs*.dat` — parse fixtures; mocked FO; `@pytest.mark.integration` runtime smoke.
- Gallery `--l3-openfoam` respects `YARD_SEA_L3_TIMEOUT` / `YARD_SEA_L3_SKIP_SOLVE`.

## Tests

- Unit (`-m 'not integration'`): **80 passed**
- `tests/test_openfoam_l3.py`: **10 passed** (+ **1 integration passed** ~20 s)

## Honesty / limits

- Coarse mesh, 3 laminar SIMPLE iterations — **exploratory ranking only**.
- Not ITTC powering / not model-test validated / not class society / not free-surface RANS.
- Cd mapped as Ct proxy with Aref≈B·T placeholder.
- Native Debian forceCoeffs FO unusable here (sha1); Docker 2412 required for coeffs on this box.
- `L3_potential` path reserved; this smoke is **`L3_rans`**.

## Re-run

```sh
cd /workspace/yard-sea-v0
export WM_PROJECT_DIR=/usr/share/openfoam FOAM_ETC=/usr/share/openfoam/etc
# if needed:
# sudo dockerd --host=unix:///var/run/docker.sock >/tmp/dockerd.log 2>&1 &
.venv/bin/python -c "
from yard_sea_v0.teachers.openfoam_l3 import run_teacher
r = run_teacher('out/sample_tapered_prism.stl', 0.2,
                'out/forcecoeffs_smoke/rerun', L=120, B=20, T=8, timeout_s=180)
print(r['fidelity'], r['Cd'], r['skipped'])
"
```
