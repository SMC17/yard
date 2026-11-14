# COLREG scenario suite v1 (`colreg_suite_v1`) — kinematics only

Modules: `tools/gym/yard_sea_v0/colreg_suite.py`, `tools/gym/yard_sea_v0/faults.py`.
Builds on `colreg_stub_v0` (#22). **Not** COLREG compliance, **not** a DNV / class /
flag-state method, **not** a replication of any published scenario catalogue.

Run: `cd tools/gym && PYTHONPATH=. python -m yard_sea_v0.colreg_suite --seeds 10 --out out/colreg.json`

## Encounters
`head_on`, `crossing_starboard` (own gives way), `crossing_port` (own stands on),
`overtaking`, `overtaken`, `multi_ship` (2–3 targets mixing the above). Seeded
bearing / speed ratio / time-to-CPA / initial CPA offset; each target is
re-classified and rejected unless it lands in the requested type.

## Variants (fault injection on perception, never on truth)
| Variant | Faults |
|---|---|
| `nominal` | none |
| `gnss_degraded` | own-position bias 150–400 m + 0.05 m/s drift + 25 m noise (targets are AIS-like absolute tracks, so the relative picture is corrupted) |
| `comms_loss` | target-track dropout for 400–600 s → dead reckoning |
| `comms_loss_manoeuvre` | as `comms_loss`, and a target alters ±25° during the blackout |

## Baseline controller and metrics
Starboard-preferring smallest alteration ≥ 30° that restores perceived passing distance;
Rule 17 stand-on with a last-resort turn; resume route when perceived clear. Own ship:
constant speed, heading rate ≤ 0.6°/s. Targets never give way (worst case for stand-on).

Ground-truth metrics: min range, collision (< 150 m), passing OK (≥ 0.8 × 926 m),
rule checks (starboard / readily apparent ≥ 30° / early TCPA ≥ 300 s / not crossing ahead;
stand-on kept course until the true last-resort condition), time-to-resolve,
cross-track deviation, return to route. All thresholds are conventions.

Baseline, 10 seeds (local run): nominal head-on / crossing-give-way / overtaking /
multi-ship 0 collisions, 100% passing; GNSS-degraded crossing 1/10 collisions;
comms-loss with a manoeuvring target drops passing to 60% — the degraded variants are
where controllers (and runtime assurance) are expected to differ.

## Rule-following targets (`simulate(..., reciprocal=True)`, `run_suite(..., reciprocal=True)`, CLI `--reciprocal`)

Each target runs its own `BaselineColregController` from its own perspective (true picture of own
ship and the other targets, same 0.6°/s rate limit): a give-way target alters to starboard, a
stand-on target keeps course until last resort, and scripted manoeuvres move the target's route.
Results record `target_behaviour` and per-target `target_logs`. Default stays `scripted`.

240-run table (6 kinds × 4 variants × 10 seeds), scripted → reciprocal:

| own controller | collisions | pass-ok | own rule-consistent |
|---|---|---|---|
| baseline | 0 % → 0.42 % | 0.963 → 0.954 | 0.917 → 0.971 |
| hold-course stand-in (no RTA) | 59.2 % → 0 % | 0.179 → 0.958 | 0.333 → 0.333 |
| hold-course + RTA | 0.42 % → 0 % | 0.933 → 0.933 | 0.917 → 0.971 |
| jitter + RTA + GNSS integrity | 1.67 % → 0 % | 0.921 → 0.979 | 0.592 → 0.592 |

Reading: with targets that follow the rules, a vessel that does nothing is rescued by the other
ship in these one-on-one geometries, so collisions alone stop discriminating; the own-ship rule
check (0.33 for hold-course) is what still exposes it. The one new baseline collision
(overtaking / comms_loss_manoeuvre / s3) is an interaction failure: own ship resumed its route once
the picture looked clear, the target then made a scripted alteration during the track blackout and
its own last-resort turn, and the stale dead-reckoned track hid it. Two copies of the same
controller are not independent agents and do not model real bridge-team behaviour.

## Stand-on behaviour: Rule 17(a)(ii) reading (baseline v1.1)

Before this change the baseline only acted as stand-on vessel at the 17(b) last-resort condition:
perceived DCPA < 0.5·dcpa_min and range < 3 km. That was late. The baseline now also takes a
17(a)(ii) action. All of the numbers below are **conventions** (`SuiteConventions`):

* The give-way vessel gets `stand_on_grace_s` = 120 s from first perceived risk.
* If its perceived course has changed by < 5° (`give_way_turn_deg`), risk persists, and perceived
  TCPA < `rule17a_tcpa_s − rule17a_perception_margin_s` (720 − 90 s), own ship alters to starboard
  only (17(c) reading). It uses the same smallest-clearing alteration grid as give-way.
* `BaselineColregController(rule17a=False)` restores the old behaviour.

The rule check (renamed `t{i}_{enc}_stand_on_rule17`) now passes a stand-on first alteration if,
on ground truth, either 17(b) held, or 17(a)(ii) held and the turn was to starboard. 17(a)(ii)
holds if the grace period has passed, true DCPA < dcpa_min, and 0 < true TCPA < 720 s. The 90 s
margin keeps GNSS bias from pushing the perceived action outside the truth window.

| (old → new) | collisions | pass-ok | rule-consistent | 5th-pct min range |
|---|---|---|---|---|
| baseline, 240 runs | 0 → 0 | 0.963 → 0.975 | 0.950 → 0.933 | 780 → 796 m |
| baseline, stand-on kinds only (80) | 0 → 0 | 0.963 → 1.000 | 0.850 → 0.800 | 773 → 900 m |
| baseline, gnss_degraded (30 seeds, 180) | 1 → 0 | 0.944 → 0.967 | 0.972 → 0.972 | 718 → 774 m |
| baseline, gnss_spoof_ramp (180) | 4 → 1 | 0.883 → 0.906 | 0.961 → 0.961 | 385 → 532 m |
| hold + RTA, 240 | 1 → 1 | 0.933 → 0.950 | 0.950 → 0.933 | 719 → 748 m |
| hold + RTA, spoof (180) | 4 → 0 | 0.878 → 0.894 | | 316 → 416 m |
| hold + RTA + GNSS, 240 | 0 → 0 | 0.963 → 0.971 | 0.954 → 0.938 | 959 → 972 m |
| hold + RTA + GNSS, gnss_degraded / spoof | 1 / 0 → 0 / 0 | 0.989 / 0.989 → 0.994 / 0.989 | → 1.000 / 0.978 | |
| baseline, reciprocal targets, 240 | 1 → 1 | 0.967 → 0.975 | 0.971 → 0.962 | |

("old" rows are rescored with the new rule check, so they differ slightly from earlier tables.)

The rule score drops only in `comms_loss_manoeuvre`. There the target really alters during the
track blackout, which removes the risk, but own ship, dead-reckoning the stale track, still takes
the 17(a)(ii) turn. The truth-based check marks that as unnecessary. This is a perception
limitation, and the check is deliberately not relaxed for it. The jitter stand-in under RTA is not
helped (4 → 5 collisions on 240), because its collisions come from the advanced policy between
fallback episodes.
