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
