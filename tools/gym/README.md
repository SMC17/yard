# Yard-Sea-v0 (tools/gym)

Evidence-coupled parametric hull **design-search gym**.

- **L0** algebraic/hydrostatic monitors (reject before CFD-rank)
- **L1** Zig HM1984 calm-water ranking when `yard_sea_zig` is built (`hm1984_zig`); Python Holtrop-simplified (`simplified_py`) fallback (not ITTC powering)
- Evidence JSON every step (ODD + claims + GSN stub)
- Search: random, hill-climb, optional BoTorch (`--botorch`; pip install botorch torch)
- Optional L2 panel/BEM: Capytaine → Cw/Cd-like (`--l2-panel`; pip install capytaine)
- Optional expensive L3 teacher: OpenFOAM forceCoeffs → `L3_rans` Cd (`--l3-openfoam`)
- Ship-D: 45-D schema + **49 algebraic constraints** + surface STL + **HP-primary ranking** (`hp_rank.rank_shipd`: calc_volumes + Michell-from-HP; env45 `use_hp_geometry` default on)

```sh
pip install -r requirements.txt
pytest -q
python -m yard_sea_v0 ingest-shipd
python -m yard_sea_v0 run-search --parents 5 --steps 40 --out out/gallery
python -m yard_sea_v0 run-search --corpus 5 --steps 40 --out out/corpus_gallery
python -m yard_sea_v0 act45 --sample 0 --steps 8
python -m yard_sea_v0 run-search --env45 --parents 3 --steps 20 --out out/env45_gallery
python -m yard_sea_v0 run-search --botorch --parents 2 --steps 8 --out out/botorch_gallery
python -m yard_sea_v0 run-search --multifidelity --l3-top 3 --botorch --parents 2 --steps 8 --out out/mf_gallery
python -m yard_sea_v0 run-search --l2-panel --parents 1 --steps 2 --out out/l2_gallery  # optional Capytaine L2
python -m yard_sea_v0 run-search --l3-openfoam --parents 1 --steps 4 --out out/l3_gallery  # optional expensive L3_rans
```

Not class/FAA/DoD approved. Public exploratory harness for SMC17/yard.

## Acceptance gate and measure-then-claim

Every oracle number now travels with an `acceptance` block (`yard_sea_v0/acceptance.py`,
schema `yard_sea_v0.acceptance.v1`) holding the individual checks and an overall `passed`.

- **L1** (`accept_l1`): finite Ct/Cf/Cw/k, Fn inside 0.10–0.35, Rn above the ITTC-57 floor,
  Ct inside an exploratory plausibility band. An L1 step that fails earns reward −1, not credit.
- **L3** (`accept_force_coeffs_file`): the whole forceCoeffs history is parsed and **Cd, Cl and
  Cm** must each be settled over the trailing 20% window (≥20 samples, band ≤1% of mean or 1e-4).
  Multi-fidelity Stage B only ranks on L3 Cd when the gate passed (`l3_accepted`).
- **Measure-then-claim** (`DesignSearchEnv.claim_done`): an episode's "done/improved" is accepted
  only after the final hull is rebuilt from its parameters and re-measured (L0 + L1 + gate); any
  claimed values must match. `run_search` uses this verdict for `improved`.

These are harness checks (iterative settling, envelope, consistency). They are not ITTC V&V,
grid-convergence studies, or class acceptance.
