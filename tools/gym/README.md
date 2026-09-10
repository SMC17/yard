# Yard-Sea-v0 (tools/gym)

Evidence-coupled parametric hull **design-search gym**.

- **L0** algebraic/hydrostatic monitors (reject before CFD-rank)
- **L1** Zig HM1984 calm-water ranking when `yard_sea_zig` is built (`hm1984_zig`); Python Holtrop-simplified (`simplified_py`) fallback (not ITTC powering)
- Evidence JSON every step (ODD + claims + GSN stub)
- Search: random, hill-climb, optional BoTorch (`--botorch`; pip install botorch torch)
- Optional expensive L3 teacher: OpenFOAM forceCoeffs → `L3_rans` Cd (`--l3-openfoam`)
- Ship-D: 45-D schema + **49 algebraic constraints** + surface STL + optional HP `calc_volumes` hydrostatics (`shipd_surface`, vendored `HullParameterization`)

```sh
pip install -r requirements.txt
pytest -q
python -m yard_sea_v0 ingest-shipd
python -m yard_sea_v0 run-search --parents 5 --steps 40 --out out/gallery
python -m yard_sea_v0 run-search --corpus 5 --steps 40 --out out/corpus_gallery
python -m yard_sea_v0 act45 --sample 0 --steps 8
python -m yard_sea_v0 run-search --env45 --parents 3 --steps 20 --out out/env45_gallery
python -m yard_sea_v0 run-search --botorch --parents 2 --steps 8 --out out/botorch_gallery
python -m yard_sea_v0 run-search --l3-openfoam --parents 1 --steps 4 --out out/l3_gallery  # optional expensive L3_rans
```

Not class/FAA/DoD approved. Public exploratory harness for SMC17/yard.
