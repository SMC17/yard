# Runtime assurance (`rta_simplex_v0`) — Simplex-style switching

Module: `tools/gym/yard_sea_v0/runtime_assurance.py` (+ `faults.py` for fault injection).

Untrusted *advanced* controller → *monitor* → *decision module* → trusted *fallback*
(running every step in shadow mode). Return to the advanced controller after
`recovery_steps` consecutive safe proposals. Every switch is logged and summarised
(`fallback_fraction`, `events`) into the scenario result / episode evidence.

**No formal guarantee.** Monitors are simple predictive checks, fallbacks are the repo's
rule-based baselines, nothing is verified or certified, and there is no claim of
conformance to any runtime-assurance standard (ASTM F3269 vocabulary only).

## Navigation (`ColregRTA`, COLREG suite v1)
Monitor `CpaMonitor`: straight-line perceived CPA of the proposed course vs.
`dcpa_min + uncertainty_m` inside `horizon_s`, plus "port turn while give-way in head-on /
starboard crossing". Fallback: `BaselineColregController`.

Measured (local, 6 kinds × 4 variants × 10 seeds = 240 runs; `HoldCoursePolicy` is a
labelled stand-in for an untrusted learned policy — no trained agent ships here):

| Controller | Collision rate | Passing OK |
|---|---|---|
| baseline alone | 0.4% | 95% |
| hold-course stand-in | 59% | 18% |
| hold-course + RTA | 0.8% | 94% |
| jitter stand-in | 20% | 23% |
| jitter + RTA | 1.3% | 86% |

Honest limit: the monitor reads the **same corrupted perception** as the policy, so under
`gnss_degraded` the RTA cannot detect the bias; raising `uncertainty_m` (e.g. 300 m) only
moves the switch earlier and did not reduce GNSS-degraded collisions in this run.
RTA quality is capped by the fallback's quality.

## Design search (`DesignSimplex`)
Wraps `DesignSearchEnv`. An action the L0 monitor would reject is replaced by the largest
`2^-k` scaling that passes (else a no-op) instead of a −1 rejection; each substitution is
written as an `rta_intervention` evidence record.

## Fault-injection hooks
`FaultInjector` (bias / drift / noise / dropout / freeze per channel, seeded, logged) and
`FaultyObservation(env, injector)` for env observations (dropout → stale hold).
