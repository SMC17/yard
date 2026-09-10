# Yard-Sea-v0 status

Implemented:
- DesignSearchEnv (Gymnasium) with L0 monitors + L1 Holtrop-simplified reward
- Evidence packs (ODD, claims, GSN stub) per step
- Random + hill-climb search (+ optional BoTorch)
- Gallery CLI + pytest
- Zig L0 mirror under `gym/`
- Soft IS-like GZ@30 bonus via `stability_bridge.py`
- GitHub Actions workflow
- **Ship-D 45-D schema** (`shipd.py`, labels from public X_LABELS.npy), sample CSV, projection → HullState, `--shipd` gallery seed

Not yet:
- Full Ship-D surface gen / 49 algebraic constraints (call into upstream Hull_Parameterization)
- CadQuery/OCCT watertight meshing
- OpenFOAM / DAFoam L3 teacher
- Full Holtrop from yard `resistance` Zig via FFI
- Strip assurance schema field-parity
