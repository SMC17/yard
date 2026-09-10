# Yard-Sea-v0 status

Implemented (on `feat/yard-sea-v0-gym`, PR #2):
- DesignSearchEnv + DesignSearchEnv45 (Ship-D seeded)
- L0 monitors, L1 Holtrop-simplified resistance, soft IS GZ@30 bonus
- Evidence packs with ODD / claims / GSN stub / **Strip assurance overlay**
- Random + hill-climb (+ optional BoTorch), gallery CLI (`--shipd`)
- Box STL export (+ optional CadQuery if installed)
- Ship-D 45-D schema, labels, sample CSV, projection → HullState
- Zig L0 mirror under `gym/`, GitHub Actions pytest+gallery
- Local: **17 pytest passed**; Ship-D gallery smoke improved Ct

Hard stops (need new deps / access / product decisions):
1. Full Ship-D surface + 49 algebraic constraints → optional dep on upstream `Hull_Parameterization` (large; matplotlib/numpy-stl)
2. Real CadQuery/OCCT Ship-D mesh (not box STL)
3. OpenFOAM / DAFoam L3 teacher (not on this machine)
4. Zig `resistance`/`hydro` FFI from yard monorepo (Zig not installed here; needs clone with Cursor GitHub app on private `yard`)
5. Harvard Dataverse 30k corpus ingest (download + license check)

Do not claim: ITTC powering, class society, FAA/ops, ITAR programs.
