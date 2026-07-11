//! Canonical m1 fixtures. The JSON files under missions/ are generated from
//! these constants (tools keep them in sync), so tests and CLI never drift.
//!
//! Climate bands are documented engineering estimates of prevailing winds on
//! the 1866 tea route (monsoon SE Asia, Indian Ocean SE trades, Agulhas
//! gales, South Atlantic trades, doldrums crossing, North Atlantic
//! westerlies). They are modeling inputs, not measured reanalysis data —
//! the validation target is aggregate passage time against the historical
//! record (85-140 days Shanghai->London), pre-registered before first run.
//!
//! Weibull structure cross-checked against published marine wind
//! climatology: shape k ~ 2 in the extratropics, rising to 3-5 in the
//! trade-wind belts (equatorward flanks of the subtropical highs), lower
//! in monsoon/variable zones — this file's 3.2 (trades) / 1.8-2.0
//! (extratropics) / 1.6 (variables) follows that pattern, and the trades'
//! lambda 7.5-8.0 with k 2.8 gives a ~7 m/s mean (Beaufort 4). Upgrade
//! path: fit per-leg parameters from ICOADS/pilot-chart reanalysis.

pub const tea_race_mission_json =
    \\{
    \\  "schema": "yard-sail-mission/v0",
    \\  "id": "m1-tea-race-1866",
    \\  "title": "Tea race - Shanghai to London, 1866 constraints",
    \\  "era_id": "clipper",
    \\  "waypoints": [
    \\    { "name": "Shanghai", "lat_deg": 31.23, "lon_deg": 121.47 },
    \\    { "name": "Sunda Strait", "lat_deg": -5.9, "lon_deg": 105.9 },
    \\    { "name": "Mauritius", "lat_deg": -20.2, "lon_deg": 57.5 },
    \\    { "name": "Cape of Good Hope", "lat_deg": -35.3, "lon_deg": 18.4 },
    \\    { "name": "St Helena", "lat_deg": -15.9, "lon_deg": -5.7 },
    \\    { "name": "Azores", "lat_deg": 38.5, "lon_deg": -28.5 },
    \\    { "name": "London", "lat_deg": 51.5, "lon_deg": 0.5 }
    \\  ],
    \\  "legs": [
    \\    { "tws_weibull_k": 1.8, "tws_weibull_lambda_mps": 6.5,
    \\      "twa_min_deg": 20, "twa_max_deg": 140,
    \\      "storm_tws_mps": 13, "storm_loss_prob": 0.008 },
    \\    { "tws_weibull_k": 3.2, "tws_weibull_lambda_mps": 8.0,
    \\      "twa_min_deg": 90, "twa_max_deg": 170,
    \\      "storm_tws_mps": 15, "storm_loss_prob": 0.003 },
    \\    { "tws_weibull_k": 2.0, "tws_weibull_lambda_mps": 10.0,
    \\      "twa_min_deg": 60, "twa_max_deg": 180,
    \\      "storm_tws_mps": 14, "storm_loss_prob": 0.010 },
    \\    { "tws_weibull_k": 3.2, "tws_weibull_lambda_mps": 7.5,
    \\      "twa_min_deg": 110, "twa_max_deg": 180,
    \\      "storm_tws_mps": 15, "storm_loss_prob": 0.002 },
    \\    { "tws_weibull_k": 1.6, "tws_weibull_lambda_mps": 6.0,
    \\      "twa_min_deg": 30, "twa_max_deg": 160,
    \\      "storm_tws_mps": 13, "storm_loss_prob": 0.003 },
    \\    { "tws_weibull_k": 1.9, "tws_weibull_lambda_mps": 9.0,
    \\      "twa_min_deg": 60, "twa_max_deg": 170,
    \\      "storm_tws_mps": 15, "storm_loss_prob": 0.006 }
    \\  ],
    \\  "segment_nm": 500.0,
    \\  "becalmed_floor_mps": 0.2,
    \\  "monte_carlo": { "runs": 300, "base_seed": 18660528 },
    \\  "gates": { "min_gm_m": 0.5, "require_is_code": true },
    \\  "objectives": [
    \\    { "id": "passage_days", "direction": "min" },
    \\    { "id": "p95_days", "direction": "min" },
    \\    { "id": "loss_rate", "direction": "min" }
    \\  ]
    \\}
;

/// Cutty Sark (1869), composite clipper. Principal particulars from the
/// ship's published record (64.7 m hull, 11.0 m beam, ~6.1 m load draft,
/// ~2,100 t displacement, ~2,970 m2 of canvas); KG, wetted surface, and Cr
/// are engineering estimates, documented as such.
pub const cutty_sark_json =
    \\{
    \\  "schema": "yard-sail-submission/v0",
    \\  "id": "cutty-sark-1869",
    \\  "author": "history",
    \\  "material": "teak",
    \\  "hull": {
    \\    "loa_m": 64.7, "beam_m": 11.0, "draft_m": 6.1, "depth_m": 7.5,
    \\    "cb": 0.55, "displacement_m3": 2080.0, "wetted_surface_m2": 1010.0,
    \\    "kg_m": 3.7, "cr": 0.0012, "form_factor": 1.2
    \\  },
    \\  "rig": { "kind": "square", "area_m2": 2970.0, "min_brace_deg": 30.0 }
    \\}
;

/// Full-bodied trader of the older school: less canvas per tonne, fuller
/// hull (higher Cr), slower — the design the clippers put out of business.
pub const indiaman_json =
    \\{
    \\  "schema": "yard-sail-submission/v0",
    \\  "id": "portly-indiaman",
    \\  "author": "yard",
    \\  "material": "oak",
    \\  "hull": {
    \\    "loa_m": 50.0, "beam_m": 12.0, "draft_m": 5.5, "depth_m": 8.0,
    \\    "cb": 0.72, "displacement_m3": 2376.0, "wetted_surface_m2": 900.0,
    \\    "kg_m": 4.0, "cr": 0.0025, "form_factor": 1.25
    \\  },
    \\  "rig": { "kind": "square", "area_m2": 1600.0, "min_brace_deg": 32.0 }
    \\}
;

/// Anachronism reference: identical to Cutty Sark but claiming a mild-steel
/// hull in the clipper era. Must die at the era gate.
pub const steel_anachronism_json =
    \\{
    \\  "schema": "yard-sail-submission/v0",
    \\  "id": "steel-anachronism",
    \\  "author": "yard",
    \\  "material": "mild_steel",
    \\  "hull": {
    \\    "loa_m": 64.7, "beam_m": 11.0, "draft_m": 6.1, "depth_m": 7.5,
    \\    "cb": 0.55, "displacement_m3": 2080.0, "wetted_surface_m2": 1010.0,
    \\    "kg_m": 3.7, "cr": 0.0012, "form_factor": 1.2
    \\  },
    \\  "rig": { "kind": "square", "area_m2": 2970.0, "min_brace_deg": 30.0 }
    \\}
;
