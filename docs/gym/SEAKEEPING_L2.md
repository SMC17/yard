# Yard-Sea-v0 seakeeping L2 (`seakeeping_l2_zero_speed_v0`)

Module: `tools/gym/yard_sea_v0/seakeeping.py`. Optional dependency: `capytaine>=3.0`
(needs `capytaine.post_pro.far_field_mean_drift_force`). Without it every sea
condition is reported `L2_seakeeping_pending` and is **not credited**.

## What it computes
| Step | Method | Honest scope |
|---|---|---|
| Geometry | Wall-sided, flat-bottom hull, half-breadth `B/2·(1-|2x/L|^p)`, `p = Cb/(1-Cb)` | Ranking geometry from `HullState`; volume matches `L·B·T·Cb` (checked) |
| Hydrodynamics | Capytaine linear BEM, deep water, head seas, **zero speed**, surge/heave/pitch | No roll, no viscous damping, `k_yy = 0.25 L` convention |
| Added resistance | Capytaine far-field (Kochin / Maruo-type) mean surge drift per ζa² | Zero-speed → low-biased vs. forward speed; use for *relative* ranking |
| Sea state | Bretschneider two-parameter spectrum (Hs, Tp), `R̄aw = 2∫S·Raw dω` | Spectral energy coverage of the ω grid is reported and gated |

## Acceptance (physics sanity, not validation)
`volume_matches_Cb`, `heave_rao_longwave_to_1`, `pitch_rao_longwave_to_k`,
`drift_longwave_to_0`, `raw_non_negative_head_seas`, `raw_finite`,
`mesh_resolves_shortest_wave` (panel ≤ λ_min/6, convention), `spectral_coverage ≥ 0.9`.
A blunt-bow sanity test checks short-wave drift approaches the ½ρgB full-reflection
limit (measured ≈0.85 at ω = 1.4 rad/s on a Cb 0.95 hull).

## Multi-condition score
`multi_condition_score(child, parent, conditions)` — calm water (L1 `Rt`) plus one or
more head seas (`Rt + R̄aw`). Per condition `d = (parent - child)/parent`;
`score = weighted_mean(d) + worst_case_weight·min(0, min d)`. A condition is credited
only when both hulls pass L1 and seakeeping acceptance.

Cost: ~4–10 s per hull (two Capytaine solves per child/parent pair), so this is a
search/gallery scoring signal, not a per-RL-step reward.

Not ITTC 7.5-02-07-02.x, not ISO 15016, not STAWAVE, not class, not model-test validated.
