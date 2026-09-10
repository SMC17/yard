# OpenFOAM L3 teacher scaffold — Yard-Sea-v0

**Date:** 2026-09-10 (America/New_York)  
**Fidelity claim:** interface + case template only → results labeled **`L3_pending`** until a real FOAM run yields `forceCoeffs`.

## Environment probe

| Capability | Present on box |
|---|---|
| `foamVersion` / `potentialFoam` / `simpleFoam` / `checkMesh` | **No** |
| `WM_PROJECT_DIR` | unset |
| Docker | **No** |
| Singularity / Apptainer | **No** |
| Podman | **No** |

→ No container pull / `potentialFoam` / `checkMesh` smoke possible on this machine.

## Delivered

1. **Teacher API** — `yard_sea_v0/teachers/openfoam_l3.py`
   - `detect_openfoam()` → availability dataclass
   - `prepare_case(stl_path, Fn, out_dir, …) → case dir` (copies template, injects STL + `__UX__` / forceCoeffs refs)
   - `run_teacher(...)` → ResistanceResult-like dict; **skips cleanly** when FOAM absent (`fidelity=L3_pending`, `skipped=True`)
   - `parse_force_coeffs` / `find_force_coeffs` for postProcessing `forceCoeffs.dat`
2. **Case template** — `cases/openfoam_hull_v0/` (also linked as `tools/gym/cases/openfoam_hull_v0/`)
   - `potentialFoam`-oriented `controlDict` + `forceCoeffs` function object placeholders
   - `blockMeshDict`, `snappyHexMeshDict`, `0/U`, `0/p`, transport/turbulence, `Allrun`
3. **CLI / gallery** — `--l3-openfoam` on `run-search`
   - Prepares/runs teacher per child STL; no-ops with pending fidelity when FOAM missing
4. **Tests** — `tests/test_openfoam_l3.py` (7 tests, mocked FOAM + forceCoeffs parse)
5. **Smoke** — `out/openfoam_smoke/case` prepared from gallery STL; run returned `openfoam_unavailable`

## Pytest

- `tests/test_openfoam_l3.py`: **7 passed**
- Full suite at scaffold time: **48 passed**

## Not done (honest hard stops)

- No real OpenFOAM solve / mesh check on box
- No Docker image pull (`opencfd/openfoam-default` etc.)
- No DAFoam adjoint path
- Cd→Ct mapping remains exploratory once FOAM exists

## How to exercise later (when FOAM available)

```sh
PYTHONPATH=. python -m yard_sea_v0 run-search --parents 2 --steps 5 --l3-openfoam --out out/l3_gallery
# or:
python -c "from yard_sea_v0.teachers import prepare_case, run_teacher; ..."
```

Not ITTC powering / not class society / not certification.
