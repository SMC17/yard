# Oracle validation vs towing-tank data

Schema `yard_sea_v0.validation.tank.v1`. Reference: `data/reference/tank_resistance_reference.json` (11 points, hulls: DTMB5415, JBC, KCS, KVLCC2).

Convention: E%D = (D - S)/D*100, model-scale C_T, C_F ITTC-57 at tank Re, no C_A. Positive E = oracle under-predicts.

## Summary per oracle

| oracle | n | mean E% | mean abs E% | RMS E% | max abs E% | validated pts (abs E <= 10%) |
|---|---|---|---|---|---|---|
| `hm1984_full` | 11 | -7.7 | 7.7 | 9.4 | 18.0 | 8/11 |
| `hm1984_gym` | 11 | -7.0 | 8.4 | 10.1 | 18.6 | 8/11 |
| `simplified_py` | 11 | +3.4 | 7.9 | 11.8 | 29.9 | 7/11 |
| `michell_l15` | 11 | -14.3 | 16.1 | 17.7 | 30.5 | 3/11 |
| `michell_l15_L2basis` | 11 | +3.6 | 11.8 | 16.8 | 45.3 | 7/11 |

## Per point (E%D)

| hull | Fn | Re | C_T meas ×10³ | `hm1984_full` | `hm1984_gym` | `simplified_py` | `michell_l15` | `michell_l15_L2basis` |
|---|---|---|---|---|---|---|---|---|
| KCS | 0.108 | 5.23e+06 | 3.796 | 3.932 (-3.6%) | 3.938 (-3.7%) | 3.934 (-3.6%) | 4.075 (-7.3%) | 3.960 (-4.3%) |
| KCS | 0.152 | 7.36e+06 | 3.641 | 3.744 (-2.8%) | 3.750 (-3.0%) | 3.718 (-2.1%) | 4.261 (-17.0%) | 3.800 (-4.4%) |
| KCS | 0.195 | 9.44e+06 | 3.475 | 3.793 (-9.2%) | 3.804 (-9.5%) | 3.618 (-4.1%) | 4.225 (-21.6%) | 3.663 (-5.4%) |
| KCS | 0.227 | 1.10e+07 | 3.467 | 4.011 (-15.7%) | 4.027 (-16.1%) | 3.601 (-3.9%) | 4.524 (-30.5%) | 3.642 (-5.0%) |
| KCS | 0.260 | 1.26e+07 | 3.711 | 4.381 (-18.0%) | 4.400 (-18.6%) | 3.628 (+2.2%) | 4.274 (-15.2%) | 3.532 (+4.8%) |
| KCS | 0.282 | 1.37e+07 | 4.501 | 4.797 (-6.6%) | 4.826 (-7.2%) | 3.669 (+18.5%) | 5.001 (-11.1%) | 3.625 (+19.5%) |
| JBC | 0.142 | 7.44e+06 | 4.289 | 4.488 (-4.6%) | 4.658 (-8.6%) | 4.258 (+0.7%) | 4.916 (-14.6%) | 4.550 (-6.1%) |
| KVLCC2 | 0.142 | 4.60e+06 | 4.110 | 4.644 (-13.0%) | 4.739 (-15.3%) | 4.560 (-10.9%) | 5.236 (-27.4%) | 4.800 (-16.8%) |
| DTMB5415 | 0.100 | 3.91e+06 | 3.930 | 4.116 (-4.7%) | 4.025 (-2.4%) | 3.915 (+0.4%) | 4.187 (-6.6%) | 4.049 (-3.0%) |
| DTMB5415 | 0.280 | 1.09e+07 | 4.193 | 4.426 (-5.6%) | 4.064 (+3.1%) | 3.757 (+10.4%) | 4.865 (-16.0%) | 3.567 (+14.9%) |
| DTMB5415 | 0.410 | 1.60e+07 | 6.460 | 6.510 (-0.8%) | 6.163 (+4.6%) | 4.529 (+29.9%) | 5.835 (+9.7%) | 3.531 (+45.3%) |

## Error by Froude band (mean abs E%)

| oracle | 0.00-0.15 | 0.15-0.22 | 0.22-0.30 | 0.30-0.50 |
|---|---|---|---|---|
| `hm1984_full` | 6.5 (n=4) | 6.0 (n=2) | 11.5 (n=4) | 0.8 (n=1) |
| `hm1984_gym` | 7.5 (n=4) | 6.2 (n=2) | 11.2 (n=4) | 4.6 (n=1) |
| `simplified_py` | 3.9 (n=4) | 3.1 (n=2) | 8.7 (n=4) | 29.9 (n=1) |
| `michell_l15` | 14.0 (n=4) | 19.3 (n=2) | 18.2 (n=4) | 9.7 (n=1) |
| `michell_l15_L2basis` | 7.6 (n=4) | 4.9 (n=2) | 11.1 (n=4) | 45.3 (n=1) |

## Empirical validity envelopes

- `hm1984_full`: Fn [0.1, 0.41], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.227, KCS@Fn=0.260, KVLCC2@Fn=0.142.
- `hm1984_gym`: Fn [0.1, 0.41], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.227, KCS@Fn=0.260, KVLCC2@Fn=0.142.
- `simplified_py`: Fn [0.1, 0.26], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.282, KVLCC2@Fn=0.142, DTMB5415@Fn=0.280, DTMB5415@Fn=0.410.
- `michell_l15`: Fn [0.1, 0.41], Cb [0.507, 0.65], Cp [0.618, 0.66], L_B [7.14, 7.45], B_T [2.98, 3.1], lcb_frac [-0.0148, -0.00683]. Failed: KCS@Fn=0.152, KCS@Fn=0.195, KCS@Fn=0.227, KCS@Fn=0.260, KCS@Fn=0.282, JBC@Fn=0.142, KVLCC2@Fn=0.142, DTMB5415@Fn=0.280.
- `michell_l15_L2basis`: Fn [0.1, 0.26], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.282, KVLCC2@Fn=0.142, DTMB5415@Fn=0.280, DTMB5415@Fn=0.410.

## Empirical drift thresholds (per oracle pair)

| seen | held-out | threshold | pairs | median | max |
|---|---|---|---|---|---|
| `hm1984_gym` | `michell_l15` | 0.180 | 40 | 0.067 | 0.225 |
| `hm1984_gym` | `simplified_py` | 0.137 | 40 | 0.049 | 0.184 |
| `hm1984_gym` | `hm1984_full` | 0.092 | 40 | 0.023 | 0.093 |
| `simplified_py` | `michell_l15` | 0.122 | 40 | 0.056 | 0.127 |

Method: quantile of |Δe_seen − Δe_holdout| over reference-point pairs (first-order error propagation); |ΔFn| <= 0.06, q = 0.95. Pairs span different hulls, so this is an upper-end estimate for the small parent→child steps a search takes; the same-hull-only variant (KCS speed pairs) is in the JSON under `drift_thresholds_same_hull`.

## Caveats

Validation of this harness's oracles against public tank data. Small sample (11 points, 4 hulls): treat envelopes as evidence bounds, not certified validity ranges. Not ITTC V&V, not class.
- Bulb, transom and C_WP are not tabulated by the sources and are omitted / estimated in `hm1984_full`.
- `michell_l15` uses the gym's synthetic Wigley-like offsets, not the real hull lines.
- Low-Fn points (Fn ≈ 0.1) carry larger tank uncertainty (3.2% for 5415).
