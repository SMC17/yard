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

## Evidence pack v2: provenance, seeds, replayable logs

`yard_sea_v0.evidence.v2` (backwards-compatible superset of v1, see `schema_compat`) adds:

- `harness`: name, version, git SHA (`YARD_GIT_SHA`/`GITHUB_SHA` or `git rev-parse`), numpy/python.
- `optimizer`: implementation, version, settings, `budget` (max evals / max wall-clock) and
  `used` (evals and wall-clock actually spent). Every `env.step` counts one eval.
- `seeds`: `base_seed`, `episode_index`, derived `episode_seed`
  (`numpy.SeedSequence(entropy=base_seed, spawn_key=(episode_index,))`). Episode ids are
  deterministic (uuid5), so policies compared at the same `(base_seed, episode_index)` share
  environment randomness. `run_search` runs random and hill-climb on the same index.
- `oracle`: fidelity and implementation that produced the number.

`env.export_log(path)` writes a JSONL log (header → records → footer). Each record carries a
sha256 over its deterministic fields, and the footer chains them. `provenance.verify_log` detects
any edit, and two replays with the same seeds produce the same `log_digest`. This is bookkeeping
for later audit tools, not a certification artefact.

## Multi-Froude reward (`reward_mode="multi_froude"`)

`DesignSearchEnv(reward_mode="multi_froude", fn_grid=..., wave_oracle="l1"|"michell")` scores each
candidate against the parent on a Froude grid (default: design Fn × 0.85 / 1.0 / 1.25). At each Fn
the resistance is split into **friction** (ITTC-57 Cf), **viscous pressure** (k·Cf) and **wave** (Cw),
and the change in each is reported as a fraction of the parent's total. Score = weighted mean ΔCt/Ct
+ `worst_case_weight` × min(0, worst ΔCt/Ct), so a hull that wins at design speed but loses
off-design is penalised. Fn points that fail acceptance are not credited, and `claim_done` in this
mode requires a positive grid score. Hill-climb look-ahead uses the same objective
(`env.candidate_reward`).

**Measured caveat:** the L1 Holtrop-style Cw here is heavily damped (about 1% of Ct at Fn 0.20), so
`wave_oracle="l1"` is close to friction-only. `wave_oracle="michell"` swaps in the vendored L1.5
Michell thin-ship Cw (about 10 ms per point), and with it the test suite shows a hull that edges the
parent at Fn 0.195 but is about 3% worse at Fn 0.25. Published RANS work on KCS reports 45–50%; this
checks the mechanism, not that magnitude.
