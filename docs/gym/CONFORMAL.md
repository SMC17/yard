# Split-conformal calibration (`conformal_split_v0`)

Modules: `tools/gym/yard_sea_v0/conformal.py` (generic, numpy) and
`tools/gym/yard_sea_v0/conformal_yard.py` (applications). Mirrored conceptually in SMC17/strip.

Score `|y−p|` or `|y−p|/|p|`; `q̂` = ⌈(n+1)(1−α)⌉-th smallest calibration score;
interval `p ± q̂` / `p(1 ± q̂)`; `q̂ = inf` when n is too small (n ≥ ⌈1/α⌉−1 needed).
Every evidence record (`type: conformal_calibration`) carries the assumptions verbatim:
exchangeability, **marginal** (not conditional) coverage, no guarantee under shift,
reference treated as exact. `group_cv` reports leave-one-group-out coverage so shift
is measured, not assumed away.

Run: `cd tools/gym && PYTHONPATH=. python -m yard_sea_v0.conformal_yard --tank-oracle hm1984_gym`

Local results (α = 0.1 unless noted):

| Application | Surrogate → reference | n | q̂ (rel) | Test / LOHO coverage |
|---|---|---|---|---|
| LF→L1.5 (exchangeable sampler) | HM1984 Zig L1 Ct → L1 viscous + Michell wave Ct | 100 cal / 100 test | 0.44 | 0.90 (random splits 0.908 ± 0.04) |
| same, Python fallback L1 | simplified_py Ct → same | 100 / 100 | 0.65 | 0.90 |
| Tank (α = 0.2) | hm1984_gym C_T → measured C_T (11 pts, 4 hulls) | 11 | 0.139 in-sample | leave-one-hull-out 0.82 |

Reading: the cheap L1 and the L1.5 composite disagree by up to ~44% (90% level) on
random hulls from the stated sampler — a large surrogate gap a multi-fidelity search
should respect. LF→L1.5 is model-vs-model (surrogate disagreement, not physical truth).
The tank calibration is physically grounded but tiny and non-exchangeable across hulls.
