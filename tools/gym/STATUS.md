# Yard-Sea-v0 status

Implemented (on `feat/yard-sea-v0-gym`, PR #2 + local Ship-D surface work):
- DesignSearchEnv + DesignSearchEnv45 (Ship-D seeded)
- L0 monitors, L1 Holtrop-simplified resistance, soft IS GZ@30 bonus
- Evidence packs with ODD / claims / GSN stub / **Strip assurance overlay**
- Random + hill-climb (+ optional BoTorch), gallery CLI (`--shipd`)
- Mesh export: CadQuery soft-chine loft (pip cadquery/ocp) + tapered-prism fallback + box; see `out/cadquery_result.md`
- Ship-D 45-D schema, labels, sample CSV, projection → HullState
- **Ship-D 49 algebraic constraints + surface STL** via vendored
  `vendor/shipd_upstream/HullParameterization.py` wrapped by
  `yard_sea_v0/shipd_surface.py` (`evaluate_constraints`, `generate_stl`);
  env45 / gallery reject infeasible before L1; `mesh.write_shipd_stl`
- Zig L0 mirror under `gym/`, GitHub Actions pytest+gallery
- Local: pytest green with constraint + STL tests (see `out/shipd_surface_result.md`)

Hard stops (need new deps / access / product decisions):
1. ~~Full Ship-D surface + 49 algebraic constraints~~ → **done locally** (vendored; NumPy-2 patches noted in vendor README)
2. Real CadQuery/OCCT Ship-D mesh (not box STL) — optional path; Ship-D STL is now real surface from HP, not OCCT B-rep
3. OpenFOAM / DAFoam L3 teacher — **interface + case template scaffolded** (`teachers/openfoam_l3.py`, `cases/openfoam_hull_v0/`, `--l3-openfoam`); runtime FOAM/docker still absent → fidelity `L3_pending`
4. Zig full HM1984/`hydro` FFI (Zig 0.15.2 installed; zig_gym L0/L1+bridge done; yard snippets vendored — wire modules next, see out/zig_result.md)
5. ~~Harvard Dataverse 30k corpus ingest~~ — done (`InputVectors_30k.npy`, `corpus.py`, Dataverse probe; see `out/dataverse_result.md`)
6. Full 45-D action space in env45 (still principal 7-D morph; constraints gate the seed vector)

Do not claim: ITTC powering, class society, FAA/ops, ITAR programs.
