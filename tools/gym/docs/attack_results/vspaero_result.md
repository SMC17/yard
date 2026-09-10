# VSPAERO result (Yard-Sea-v0 Strip)

**Date:** 2026-09-10 17:50 EDT  
**Status:** **PASS** — real CL/CD/CM from vendored OpenVSP `vspscript` + `vspaero`

## Outcome

| Item | Result |
|------|--------|
| `vspscript` | `vendor/openvsp/vspscript` (OpenVSP 3.51.3) |
| `vspaero` | `vendor/openvsp/vspaero` |
| Teacher | `yard_sea_v0.teachers.vspaero_l1` (fidelity `aero_vspaero_l1`) |
| `openvsp_stub.run()` | Delegates to VSPAERO when `vspaero` present → real coeffs |
| Geometry | Thin rectangular wing (chord 1, area 6, Tess_W 33, SectTess_U 8) |
| Analyses | `VSPAEROComputeGeometry` → `VSPAEROSweep` (α=2°, Mach=0.1, WakeNumIter=3, NCPU=1) |
| **CL** | **0.182078** |
| **CD** | **0.00629931** |
| **CM** (CMytot) | **-0.0411911** |
| Coeff source | stdout markers `yard_sea_CL/CD/CM=` (polar fallback also implemented) |
| Artifacts | `out/vspaero_smoke/yard_sea_vspaero.{vsp3,polar,history,…}` |
| Tests | `tests/test_aero_stubs.py` — **12 passed** |

## How it runs

1. AngelScript builds a thin wing, `WriteVSPFile`, clear/reload.
2. `ExecAnalysis("VSPAEROComputeGeometry")` writes DegenGeom / `.vspgeom`.
3. `ExecAnalysis("VSPAEROSweep")` launches sibling `vspaero` (PATH prepends `vendor/openvsp`).
4. Results from `FindLatestResultsID("VSPAERO_History")` → `CLtot` / `CDtot` / `CMytot` (last wake iter).
5. Markers printed for Python parse; `*.polar` parsed as backup.

CLI equivalent:

```bash
cd /tmp/work
PATH=vendor/openvsp:$PATH vspscript -script yard_sea_vspaero.vspscript
```

**Gotcha fixed:** pass script **basename** with `cwd=work.resolve()` — relative paths like `out/foo/script.vspscript` make AngelScript fail with `Error ExecuteScript GetModule`.

## API

```python
from yard_sea_v0.teachers import vspaero_l1, openvsp_stub

print(vspaero_l1.detect())
print(vspaero_l1.run(alpha_deg=2.0, work_dir="out/vspaero_smoke"))
print(openvsp_stub.run(alpha_deg=2.0))  # same coeffs when vspaero present
```

## Honesty

Vortex-lattice exploratory ranking only. **Not** certification, FAA, class society, or operational aero. Default vehicle is an in-script rectangular wing (not a loaded `.vsp3` hull/airframe yet).

## Docs touched

- `docs/OPENVSP_INSTALL.md` — stub now wires VSPAERO
- `docs/STRIP_ORACLES.md` — `vspaero_l1` gate row
- No GitHub push
