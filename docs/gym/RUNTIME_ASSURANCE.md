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

## GNSS integrity monitor (`GnssIntegrityMonitor`, `gnss_dr_innovation_v0`)

`ColregRTA(gnss_monitor=GnssIntegrityMonitor())`. Dead reckoning from the perceived heading and
speed (gyro / log; the suite gives them a constant 0.5° / 0.03 m/s bias, `DR_SENSOR_BIAS`,
convention) is propagated independently of GNSS; consistent fixes update it with a scalar Kalman
gain. Two χ²(2) tests at α = 0.001 (13.8): per-fix `|ν|²/(P+R)` and a 12-fix (60 s) windowed mean
`|ν̄|²/((P+R)/n)` for slow pull-offs. The first failure latches `suspect`: the RTA then navigates on
DR, widens the CPA allowance by 2σ_DR, and keeps the fallback in control (an advanced policy that
perceives the bad fix is not handed back control in v0). Conventions: σ_GNSS 25 m, σ_v 0.15 m/s,
trusted pre-run fix σ 10 m (`ColregRTA.reset(own0)`, called by `simulate`). An innovation-
monitoring heuristic — not RAIM, not a certified integrity monitor, no guarantee.

New opt-in variant `gnss_spoof_ramp` (not in the default 240-run table): GNSS correct, then a
0.5–1.5 m/s pull-off starting 700–1000 s before CPA, plus 25 m noise.

### Results (30 seeds × 6 kinds = 180 runs per variant; collisions are counts)

| config | gnss_degraded coll / pass-ok | gnss_spoof_ramp coll / pass-ok |
|---|---|---|
| baseline, no RTA | 1 / 0.944 | 4 / 0.883 |
| baseline + RTA (CPA only) | 1 / 0.944 | 4 / 0.883 |
| baseline + RTA + GNSS integrity | 1 / 0.989 | **0** / 0.989 |
| hold-course stand-in + RTA | 2 / 0.894 | 4 / 0.878 |
| hold-course stand-in + RTA + GNSS | 1 / 0.989 | **0** / 0.989 |
| jitter stand-in + RTA | 1 / 0.889 | 2 / 0.761 |
| jitter stand-in + RTA + GNSS | 1 / 0.989 | **0** / 0.883 |

* Detection: 100 % of faulted runs flagged; gnss_degraded at t = 0 (bias vs trusted pre-run fix;
  with first-fix initialisation instead, the 0.05 m/s drift is still caught by the window test in
  99.4 %); spoof ramp median 368 s after scenario start (onset is 0–800 s).
* False alarms: 0 / 540 on nominal, comms_loss, comms_loss_manoeuvre.
* The one remaining gnss_degraded collision (crossing_port s13) happens with GNSS already rejected
  and DR accurate (σ ≈ 20 m): a stand-on case where the target never gives way and the baseline's
  last-resort turn is too late. That is a fallback-policy limitation, not a navigation one.
* Default 240-run table (10 seeds), CPA-only RTA → RTA + GNSS: hold stand-in collisions 0.42 % → 0 %,
  pass-ok 0.933 → 0.963; baseline 0 % → 0 %, pass-ok 0.963 → 0.971; jitter 1.67 % → 1.67 % (its
  collisions are in nominal / comms_loss_manoeuvre, not GNSS).
* Adding the DR sensor bias changed the perceived heading by 0.5°, which moved the earlier 10-seed
  gnss_degraded baseline from 1 collision to 0; with the bias removed, 30 seeds gives baseline 2,
  hold + RTA 2, hold + RTA + GNSS 1. Collision counts at this level are seed-sensitive. Pass-ok
  (≥ 0.8·dcpa_min) and the 5th-percentile minimum range (≈ 700 m → ≈ 1010 m on gnss_degraded,
  ≈ 385 m → ≈ 1030 m on the spoof ramp, baseline configs) are the steadier signal.

### v1: re-trust with hysteresis (`gnss_dr_innovation_v1`)

Changes from v0:
* **Detection levels.** The per-fix test is now at α = 1e-5 and the 60 s window test at α = 1e-4,
  using exact χ²(2) quantiles (−2 ln α). With 25 m noise and about 600 fixes per run, the old
  per-fix 1e-3 would have false-alarmed in roughly half of all noisy runs.
* **Window test variance** is now `P + R/n`. The DR error is common to all fixes in the window;
  only the GNSS noise averages down.
* **DR bias growth while coasting.** σ_bias = 0.1 m/s · τ (convention, at least the suite's injected
  0.5° / 0.03 m/s) is added to the random-walk P.
* **Re-trust.** While suspect, each fix is still tested against the coasting DR state at
  α = 0.01. After `retrust_n` (default 24, i.e. 2 min) consecutive fixes pass both the per-fix and
  window tests, GNSS is re-admitted with the grown P, and the stale innovation window is cleared.
  Re-trust is not attempted once σ_DR > `retrust_max_sigma_m` (40 m, about 400 s of coasting):
  beyond that a 120–150 m bias can no longer be told apart from DR drift, so the monitor stays on
  DR. `retrust_n=None` restores v0 latching.
* **New opt-in variant `gnss_glitch`:** a 150–400 m step starting at 100–400 s and clearing after
  200–400 s, with 25 m noise throughout.
* The summary keeps `suspect` as "ever flagged" and adds `suspect_at_end`, `events` and `n_retrust`.

Results: hold-course stand-in + RTA + GNSS, 30 seeds × 6 kinds = 180 runs per variant. A false
alarm is a flag raised while no position fault is active. A wrong re-trust is a re-trust while the
injected offset is > 75 m.

| variant | metric | latch (v0) | N = 24 (default) | N = 12 |
|---|---|---|---|---|
| nominal / comms_loss / comms_loss_manoeuvre (540) | runs with a false alarm | 0 | 0 | 0 |
| gnss_degraded (persistent bias) | flagged / re-trusted / wrong re-trust | 180 / 0 / 0 | 180 / 0 / 0 | 180 / 0 / 0 |
| gnss_spoof_ramp | flagged / re-trusted / wrong re-trust | 180 / 0 / 0 | 180 / 0 / 0 | 180 / 0 / 0 |
| gnss_glitch | runs re-trusted | 0 | 43 | 102 |
| gnss_glitch | median recovery after the glitch clears | – | 158 s | 95 s |
| gnss_glitch | false re-alarms after re-trust (runs) | – | 2 | 6 |
| gnss_glitch | fallback share | 0.98 | 0.81 | 0.56 |
| gnss_glitch | collisions / pass-ok | 1 / 0.994 | 1 / 0.994 | 1 / 0.994 |
| synthetic noisy unbiased GNSS (unit test, 20 × 600 fixes) | runs flagged | | ≤ 1 | |

No wrong re-trusts were seen in any configuration. The main limit on recovery is the 40 m DR-sigma
cap: glitches that leave the ship coasting for longer than about 400 s are never re-admitted.
That is deliberate, because availability is traded for not re-admitting a biased fix. Lowering N
roughly halves recovery time, at the cost of a few false re-alarms. The one glitch collision does
not change with the re-trust setting.
