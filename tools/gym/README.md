# Yard-Sea-v0 (tools/gym)

Evidence-coupled parametric hull **design-search gym**.

- **L0** algebraic/hydrostatic monitors (reject before CFD-rank)
- **L1** Zig HM1984 calm-water ranking when `yard_sea_zig` is built (`hm1984_zig`); Python Holtrop-simplified (`simplified_py`) fallback (not ITTC powering)
- Evidence JSON every step (ODD + claims + GSN stub)
- Search: random, hill-climb, optional BoTorch (`--botorch`; pip install botorch torch)
- Optional L2 panel/BEM: Capytaine → Cw/Cd-like (`--l2-panel`; pip install capytaine)
- Fidelity as an action: `fidelity.FidelityChoiceEnv` (Box(8): morph + oracle choice), explicit cost budget, LF-mistrust fallback to HF, HF-measured claims
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

## Held-out oracle check and long-horizon drift (`--holdout`)

`run-search --holdout` (or `run_search(..., holdout=True)`) re-scores every final design *after*
search with an oracle the policy never saw. By default that is L1 viscous + L1.5 Michell wave
averaged over the Froude grid (`holdout.make_holdout_fn`). Rewards are byte-identical with and
without `--holdout`, and a test enforces it.

- `holdout_check`: Spearman rank agreement, sign agreement, and a per-design `exploit` flag
  (the reward oracle claims an improvement but the held-out oracle says the design is worse).
- `trajectory_drift`: |seen − held-out| at **every** step of the episode, with final/max error and
  slope, so surrogate error is judged on the long horizon rather than only the first step.
- The gallery manifest gets a `holdout` summary (claimed / confirmed / exploit, max final drift).

### Long-horizon drift flag (`--drift-horizon`, `--drift-threshold`)

With `--holdout`, every episode also gets a `drift_check` record (`holdout.long_horizon_drift_check`).
It goes in the evidence directory, the episode log, and `row["drift"]["long_horizon"]`.

- **What is measured:** at each accepted step, `seen` and `held-out` are each the *cumulative*
  relative Ct improvement vs the parent. So `|seen − held-out|` is the cumulative error of the
  surrogate against the reference, as a fraction of parent Ct.
- **Horizon:** the number of accepted steps checked. The default is the full episode, because a
  short horizon misses drift that only shows up late, and a test covers that case.
- **Threshold:** the default is resolved **per oracle pair from measured tank data**
  (`holdout.resolve_drift_threshold`, `threshold_source: empirical_tank_validation`). For two
  oracles with relative errors e_a, e_b vs truth, a parent→child step changes their improvement
  estimates by Δe_a − Δe_b to first order; the default is the 95th percentile of
  |Δe_a − Δe_b| over all pairs of measured reference points (|ΔFn| ≤ 0.06) in
  `reports/validation/oracle_tank_validation.json`. HM1984 reward vs Michell held-out: **0.180**
  (40 pairs; same-hull-only 0.177). Pairs the report does not cover (Capytaine box proxy, or a
  held-out oracle sharing the reward's wave model) fall back to the **0.10** convention
  (`default_convention_not_validated`). The derivation is copied into `threshold_derivation`.
  `--drift-threshold` still overrides (`threshold_source: user`). `exceeded` is set when the max
  error within the horizon is above the threshold; `first_exceeding_step` says where.
- **Flag only:** `affects_reward: false`. Rewards are byte-identical with and without the check,
  and a test enforces it.

Example: 3 parents × 2 policies, 30 steps, seed 0, HM1984 reward vs the Michell held-out oracle
(Michell wave term on the wetted-surface basis, yard#29). Max drift ranged 0.14–0.39; at the old
0.10 convention all 6 episodes were flagged (no discrimination), at the empirical 0.18 default 3 of
6 are, first exceeding at steps 3, 9 and 11. Both oracles are models, so a flag means "the
disagreement is larger than their measured errors explain", not "the surrogate is wrong".

### Tank validation and applicability envelope

`python -m yard_sea_v0.validation reports/validation` re-scores every resistance oracle on public
towing-tank C_T (KCS ×6 Fn, JBC, KVLCC2, DTMB 5415 ×3; `data/reference/`, catalogue in
`data/CATALOG.md`). Mean |E%D|: HM1984 (gym mapping) 8.4%, Python simplified 7.9%, Michell
(synthetic offsets) 16.1%. Every L1 acceptance block and evidence pack then carries an
**advisory** applicability record (`yard_sea_v0.applicability`): inside the method's declared
range, and inside the box of reference points where that oracle was within ±10% (and not nearest
to a failed point). Outside → `outside_validated_envelope` claim with status `flagged`; reward and
the acceptance verdict are unchanged.

`--holdout-oracle` selects the held-out oracle (`holdout.make_holdout_fn(oracle=...)`):

| oracle | model | sees | notes |
|---|---|---|---|
| `michell` (default) | L1 viscous + Michell L1.5 thin-ship wave, Froude grid | all 7 params | |
| `hm1984` | Zig Holtrop-Mennen 1984 L1, Froude grid | all 7 params | Unavailable (NaN, `available=false`) without `zig_gym`; never falls back to the Python L1 |
| `capytaine_l2` | Capytaine linear BEM on an L×B×T box at design Fn | L, B, T | A radiation-damping proxy, closer to seakeeping than to calm-water resistance. Designs that only change Cb/lcb/kg/Fn are `blind`, not scored 0 |

Every row records `reward_wave_model`, `holdout_wave_model` and `independent_of_reward`. With
`zig_gym` built, the default L1 reward *is* HM1984, so `--holdout-oracle hm1984` is flagged
`independent_of_reward=false`. In that case it is a consistency check, not a held-out one.
Blind and NaN rows are left out of the agreement stats.

Example (3 parents × 2 policies, 12 steps, seed 0, HM1984 reward). These numbers show how the
oracles behave and are not a validation result:

| oracle | independent | claimed | confirmed | exploit |
|---|---|---|---|---|
| michell | yes | 6 | 4 | 2 |
| hm1984 | no | 6 | 5 | 1 |
| capytaine_l2 | yes | 6 | 2 | 4 |

The oracles disagree with each other, and that disagreement is the signal. Each one is a second
model, not ground truth, and none of this is ITTC / class.

## COLREG encounter scenario stub (`colreg_stub.py`, label `colreg_stub_v0`)

This is a geometry-only stub for scenario-based collision-avoidance testing. It is **not** a COLREG
compliance check and **not** a DNV, class or flag-state method. It borrows only the layout of
scenario-based testing: a parameterised encounter, then the expected own-ship role, then one
manoeuvre evaluated against simplified readings of the rules.

- `classify(own, target)` returns head-on (Rule 14), crossing starboard/port (Rule 15),
  overtaking/overtaken (Rule 13), CPA/TCPA, and the own-ship role
  (`give_way` / `stand_on` / `none`) when DCPA and TCPA are inside the thresholds.
- `evaluate_manoeuvre(own, target, alteration_deg)` applies an instantaneous course change. It
  then checks four things: the turn is to starboard, the turn is "readily apparent" (Rule 8(b)),
  the resulting passing distance, and that own ship does not cross ahead of the target. For a
  stand-on vessel it instead checks that course is kept (Rule 17(a)(i)).
- `scenario_suite()` builds a deterministic grid of collision-course encounters (CPA = 0).
- The numeric thresholds in `Thresholds` are conventions, not rule text: 0.5 nmi DCPA, 20 min
  TCPA, a ±6° head-on sector, and a 30° minimum alteration.
- Not modelled: restricted visibility, narrow channels/TSS, vessel categories, multi-ship
  encounters, ship dynamics, environment, sensor uncertainty, good seamanship.
