# Yard-Sea-v0 status

Implemented (on `feat/yard-sea-v0-gym` / remaining-stones + local BoTorch/L3 loop):
- DesignSearchEnv (7-D principal morph) **kept intact**
- **DesignSearchEnv45 — true Box(45) Ship-D actions** (relative deltas, 30k 1–99% clamps)
- L0 monitors, L1 Holtrop-simplified resistance, soft IS GZ@30 bonus
- Evidence packs with ODD / claims / GSN stub / **Strip assurance overlay**
- Random + hill-climb (+ **BoTorch** via `--botorch`), gallery CLI (`--shipd`, `--env45`, `--botorch`, `--l3-openfoam`, `--l15-michell`, `act45`)
- Mesh export: CadQuery soft-chine loft (pip cadquery/ocp) + tapered-prism fallback + box; see `out/cadquery_result.md`
- Ship-D 45-D schema, labels, sample CSV, projection → HullState
- **Ship-D 49 algebraic constraints + surface STL** via vendored
  `vendor/shipd_upstream/HullParameterization.py` wrapped by
  `yard_sea_v0/shipd_surface.py` (`evaluate_constraints`, `generate_stl`, `calc_volumes`);
  env45 rejects infeasible **actions** before L1; `mesh.write_shipd_stl`
- **HP Calc_Volumes hydrostatics** — `calc_volumes` / `hull_from_volumes`; optional env45 `use_hp_hydro`
- **Michell L1.5 Ship-D waterlines** — `teachers.michell_l15.shipd_waterline_offsets` via HP `gen_MeshGridWL`; Wigley fallback retained (`out/michell_wl_result.md`)
- Zig L0 mirror under `gym/`, GitHub Actions pytest+gallery
- Local: pytest green with constraint + STL + act45 tests (see `out/shipd_surface_result.md`, `out/act45_result.md`)

Hard stops (need new deps / access / product decisions):
1. ~~Full Ship-D surface + 49 algebraic constraints~~ → **done locally** (vendored; NumPy-2 patches noted in vendor README)
2. Real CadQuery/OCCT Ship-D mesh (not box STL) — optional path; Ship-D STL is now real surface from HP, not OCCT B-rep
3. OpenFOAM L3 teacher — **snappyHexMesh + forceCoeffs working** (`teachers/openfoam_l3.py`, `cases/openfoam_hull_v0/`, `--l3-openfoam`); prefers **native** simpleFoam with SHA1 preload (`tools/foam_sha1_fix/`) when healthy, else Docker 2412 → fidelity **`L3_rans`** (see `out/native_forces_result.md`, `out/forcecoeffs_result.md`); DAFoam adjoint still absent; gallery records child `Cd` / `l3_fidelity` from forceCoeffs teacher (see `out/botorch_l3_loop_result.md`)
4. Zig full HM1984/`hydro` FFI (Zig 0.15.2 installed; zig_gym L0/L1+bridge done; yard snippets vendored — wire modules next, see out/zig_result.md)
5. ~~Harvard Dataverse 30k corpus ingest~~ — done (`InputVectors_30k.npy`, `corpus.py`, Dataverse probe; see `out/dataverse_result.md`)
6. ~~Full 45-D action space in env45~~ → **done** (`env45.py` Box(45); constraints → project_to_hull → L0 → L1; see `out/act45_result.md`)
7. ~~Cheap Ship-D **surface hydrostatics**~~ → **done** (`shipd_surface.calc_volumes` / `Calc_VolumeProperties`; env45 `use_hp_hydro=True`, `hp_hydro_every_n`; default still `project_to_hull` — see `out/calc_volumes_result.md`)

Do not claim: ITTC powering, class society, FAA/ops, ITAR programs.

## VSPAERO (2026-09-10)

Real CL/CD/CM via `teachers.vspaero_l1` + `openvsp_stub` delegation. See `out/vspaero_result.md`.
