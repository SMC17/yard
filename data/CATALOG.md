# Yard data catalog

Public / OSINT reference data for the Yard-Sea gym. Nothing here is classified,
CUI or ITAR-controlled. Every entry records licence and citation; the
machine-readable twin is [`catalog.yaml`](catalog.yaml).

| Status | Meaning |
|---|---|
| **ingested** | individual factual values quoted with citation in `reference/` (raw file not redistributed) |
| **vendored** | file committed under `vendored/` because its licence allows redistribution |
| **fetch-script** | `python data/fetch/fetch_yard_data.py` downloads it into `data/cache/` (git-ignored) and checks sha256 |
| **catalogued** | URL + licence recorded, not pulled yet (reason given) |
| **not-usable** | cannot be represented by the current oracles (reason given) |

## Summary

| id | quantities | licence | status | used for |
|---|---|---|---|---|
| `t2015_kcs_case21` | KCS C_T, sinkage, trim at 6 Fn | unspecified (public) | ingested + fetch-script | oracle validation, envelope, drift threshold |
| `t2015_jbc_case11a` | JBC C_T at Fn 0.142 | unspecified (public) | ingested + fetch-script | validation at C_B 0.858 |
| `g2010_kvlcc2_moeri` | KVLCC2 C_T at Fn 0.142 | cited value | ingested | validation, full-form tanker |
| `ittc_5415_cssrc` | DTMB 5415 C_T at Fn 0.10/0.28/0.41 + uncertainty | cited values (ITTC) | ingested | validation incl. high Fn |
| `simman_particulars` | KCS / KVLCC2 / 5415 particulars, IGES lines | unspecified | ingested (particulars) | model-scale particulars |
| `t2015_kcs_hull_sva` | KCS hull NURBS (IGES), full scale | unspecified | fetch-script | real-hull Michell, HM bulb/transom inputs |
| `g2000_kvlcc2_offsets` | KVLCC2 body-plan offsets | unspecified | fetch-script | real-hull Michell, HM bulb inputs |
| `g2000_dtmb5415_surface_grid` | 5415 structured surface grid | unspecified (IGES says copyrighted) | fetch-script | real-hull Michell, transom A_T |
| `t2015_jbc_iges` | JBC hull IGES (trimmed surfaces) | unspecified | catalogued | needs trimmed-surface support |
| `korkmaz2021_kvlcc2_ballast` | KVLCC2 ballast C_T curve | CC BY 4.0 | not-usable | trimmed ballast not representable by HullState |
| `ittc_5415_facility_bias` | tank-to-tank scatter | ITTC | catalogued | envelope tolerance floor |
| `dsyhs_4tu` | DSYHS full measurement set | CC0 | vendored (upright bare-hull subset, CSV) + fetch-script | 500 measured C_T points, out-of-population check |
| `dsyhs_hydrostatics_4tu` | DSYHS canoe-body hydrostatics | CC0 | vendored (upright, CSV) + fetch-script | joins the measurements; S_c, C_B, C_P, LCB |
| `uci_yacht_hydrodynamics` | DSYHS series-1 residuary resistance, 308 runs | CC BY 4.0 | vendored | out-of-envelope negative control |
| `shipd` | 30k parametric hulls + Michell C_w | CC0 | ingested (sample) | 45-D action space, L1.5 |
| `mit_bluff_body_wakes` | DNS + PIV wakes, 9 bodies | per host | catalogued | L3 wake validation |
| `turtles` | 3D turbulent wakes, 14 TB | per host | catalogued | long-rollout drift (sample only) |
| `wigley_cooperative` | Wigley C_T / C_W | n/a | catalogued | cleanest Michell check (no open table found) |
| `series60` | Series 60 C_R | US Gov | catalogued | systematic series (needs digitising; no invented values) |
| `wageningen_b` | B-series K_T/K_Q | published coeffs | catalogued | propulsion teacher |
| `simman_kcs_5415_propeller_openwater` | open-water K_T/K_Q | unspecified | catalogued | propulsion validation |
| `capytaine_wamit_benchmarks` | BEM radiation/diffraction | GPL-3.0 | catalogued | L2 self-verification |
| `dtc_duisburg` | DTC geometry + resistance | open access | catalogued | extra container ship |

Count: 23 entries — 5 ingested (11 measured C_T points + particulars), 3 vendored
(UCI yacht; DSYHS measurements + hydrostatics as derived CSV, CC0), 4 fetch-script-only
(DSYHS overview; KCS, KVLCC2 and 5415 hull lines), 1 not-usable, 10 catalogued.

Hull lines are read by `tools/gym/yard_sea_v0/hull_lines.py`; its derived volume, C_B,
LCB and wetted surface are checked against the published particulars in
`tools/gym/tests/test_hull_lines.py` (volume within 1 %, S within 4 %).

## How the data are used

* `tools/gym/yard_sea_v0/validation.py` evaluates every resistance oracle on the
  ingested tank points and writes `tools/gym/reports/validation/oracle_tank_validation.{md,json}`.
* The per-oracle empirical envelope from that report feeds the acceptance gate
  as an *advisory* applicability check (recorded in evidence; does not change reward).
* The long-horizon drift threshold default per oracle pair is derived from the
  same report (see the report's "Empirical drift thresholds" section).

## Rules

* Never commit a raw file whose licence is unstated or forbids redistribution:
  add it to `fetch/fetch_yard_data.py` with its sha256 instead.
* Never type in numbers that were not read from a source; if a table needs
  digitising, catalogue it and say so.
