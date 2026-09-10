# Yard-Sea-v0 status

Implemented (2026-09-10):
- DesignSearchEnv (Gymnasium) with L0 monitors + L1 Holtrop-simplified reward
- Evidence packs (ODD, claims, GSN stub) per step
- Random + hill-climb search (+ optional BoTorch)
- Gallery CLI + pytest (7 tests)
- Zig L0 mirror under `gym/`
- Soft IS-like GZ@30 bonus via `stability_bridge.py`
- GitHub Actions workflow

Not yet (blocked on data/deps/time):
- Ship-D / C-ShipGen public corpus ingest + real 45-D params
- CadQuery/OCCT watertight meshing
- OpenFOAM / DAFoam L3 teacher
- Full Holtrop from yard `resistance` Zig via FFI
- Strip assurance schema field-parity
- Learning-in-ops (intentionally out of scope)
