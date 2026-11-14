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
