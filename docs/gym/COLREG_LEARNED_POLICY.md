# Small learned COLREG policies + Simplex (`colreg_learn_v0`)

Module `tools/gym/yard_sea_v0/colreg_learn.py`; shipped CEM weights `tools/gym/policies/colreg_cem_v0.json`.
These are deliberately small learners, run so the runtime-assurance wrapper is measured around a
real learned controller instead of the hold-course / jitter stand-ins. They are not good, safe or
COLREG-compliant controllers.

* **Observation**: route-relative own heading (sin, cos), then for the two most dangerous
  *perceived* targets (smallest CPA with 0 < TCPA < 1500 s, else nearest): presence, body-frame
  relative position and velocity, DCPA, TCPA, and give-way / stand-on flags from the
  `colreg_stub` geometry (20 features). Faulted perception goes straight in.
* **Action**: heading alteration ±90° from the route (rate-limited by the suite dynamics).
* **Episode cost** (ground truth): 100·collision + 20·passing shortfall/dcpa_min + 5·(own rule
  check failed) + 2·cross-track/5 km + 1·(not back on route).
* **Training**: generator seeds 1000–1003 × 6 kinds × {nominal, gnss_degraded, comms_loss}
  (72 scenarios). The evaluation table uses seeds 0–9 × 4 variants (240 runs, disjoint scenarios).
  * CEM: 20→8→1 tanh MLP (177 parameters), population 48, 15 % elite, 25 iterations (8 processes,
    ≈ 12 min). Train cost 3.58.
  * PPO (stable-baselines3 2.9.2, optional dependency): `ColregGymEnv` over `simulate_iter`, a
    decision every 30 s, dense truth-based shaping (range inside dcpa_min, cross-track) plus terminal
    episode cost / 10; MLP [32, 32], 1 M steps, 8 envs, ≈ 3 min. Weights not committed (rebuild
    with `python -m yard_sea_v0.colreg_learn ppo --steps 1000000 --out ppo.zip`).

## Results (240 held-out runs; `python -m yard_sea_v0.colreg_learn eval-shipped` reproduces the CEM rows)

| controller | wrapper | collisions | pass-ok | own rule-consistent | mean cost | fallback share |
|---|---|---|---|---|---|---|
| rule baseline | none | 0 % | 0.963 | 0.917 | 1.48 | – |
| rule baseline | RTA + GNSS integrity | 0 % | 0.971 | 0.954 | 1.24 | 0.30 |
| CEM MLP | none | 1.25 % (3) | 0.908 | 0.696 | 5.30 | – |
| CEM MLP | RTA (CPA monitor) | 0 % | 0.954 | 0.696 | 3.61 | 0.06 |
| CEM MLP | RTA + GNSS integrity | 0 % | 0.963 | 0.767 | 2.95 | 0.29 |
| PPO 1 M | none | 1.67 % (4) | 0.888 | 0.575 | 6.12 | – |
| PPO 1 M | RTA (CPA monitor) | 0 % | 0.933 | 0.575 | 4.25 | 0.12 |
| PPO 1 M | RTA + GNSS integrity | 0 % | 0.958 | 0.679 | 3.38 | 0.34 |

Bare-policy collisions occur only in gnss_degraded and comms_loss_manoeuvre (CEM 1 + 2, PPO 2 + 2).

Reading:
* Both learned policies are worse than the hand-written baseline on every metric. Their
  rule-consistency is low: they often pass with a large or late alteration rather than an early,
  readily apparent starboard turn.
* The Simplex wrapper removes every bare-policy collision on this table, at a 6–12 % fallback share
  (CPA monitor), or about 30 % when GNSS integrity is on. In that case the fallback keeps control
  for the whole run once GNSS is flagged, by design. The wrapper does not fix rule-consistency,
  because the monitor only checks CPA and port turns.
* With 240 runs and only 3–4 bare collisions, the "0 %" rows carry wide uncertainty: the 95 %
  upper bound is about 1.2 %. This is not a safety claim.
* An untrained PPO (16 k steps) had 0 bare collisions but rules 0.26: it swerves wide. Collisions
  alone reward that, which is why the table carries the rule and cost columns.
