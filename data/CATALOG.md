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
| `korkmaz2021_kvlcc2_ballast` | KVLCC2 ballast C_T curve | CC BY 4.0 | not-usable | trimmed ballast not representable by HullState |
| `ittc_5415_facility_bias` | tank-to-tank scatter | ITTC | catalogued | envelope tolerance floor |
| `dsyhs_4tu` | DSYHS full measurement set | CC0 | fetch-script | yacht / planing envelope (needs hydrostatics) |
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

Count: 18 entries — 5 ingested (11 measured C_T points + particulars), 1 vendored,
2 fetch-script-only (DSYHS), 1 not-usable, 9 catalogued.

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
