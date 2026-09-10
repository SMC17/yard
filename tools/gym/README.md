# Yard-Sea-v0 (tools/gym)

Evidence-coupled parametric hull **design-search gym**.

- **L0** algebraic/hydrostatic monitors (reject before CFD-rank)
- **L1** Holtrop-simplified calm-water ranking (not ITTC powering)
- Evidence JSON every step (ODD + claims + GSN stub)
- Search: random, hill-climb, optional BoTorch

```sh
cd tools/gym
pip install -r requirements.txt
PYTHONPATH=. pytest -q
PYTHONPATH=. python -m yard_sea_v0 run-search --parents 5 --steps 40 --out out/gallery
```

Not class/FAA/DoD approved. Public exploratory harness for SMC17/yard.
