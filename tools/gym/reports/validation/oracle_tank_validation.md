# Oracle validation vs towing-tank data

Schema `yard_sea_v0.validation.tank.v1`. Reference: `data/reference/tank_resistance_reference.json` (11 points, hulls: DTMB5415, JBC, KCS, KVLCC2).

Convention: E%D = (D - S)/D*100, model-scale C_T, C_F ITTC-57 at tank Re, no C_A. Positive E = oracle under-predicts.

## Summary per oracle

| oracle | n | mean E% | mean abs E% | RMS E% | max abs E% | validated pts (abs E <= 10%) |
|---|---|---|---|---|---|---|
| `hm1984_full` | 11 | -6.6 | 6.9 | 8.3 | 17.5 | 8/11 |
| `hm1984_full_bare` | 11 | -7.7 | 7.7 | 9.4 | 18.0 | 8/11 |
| `hm1984_gym` | 11 | -5.3 | 7.4 | 8.8 | 19.5 | 8/11 |
| `hm1984_gym_bare` | 11 | -7.0 | 8.4 | 10.1 | 18.6 | 8/11 |
| `simplified_py` | 11 | +3.2 | 8.9 | 12.7 | 30.3 | 7/11 |
| `simplified_py_bare` | 11 | +3.4 | 7.9 | 11.8 | 29.9 | 7/11 |
| `michell_l15` | 11 | -14.3 | 16.1 | 17.7 | 30.5 | 3/11 |
| `michell_l15_L2basis` | 11 | +3.6 | 11.8 | 16.8 | 45.3 | 7/11 |

## Per point (E%D)

| hull | Fn | Re | C_T meas ×10³ | `hm1984_full` | `hm1984_full_bare` | `hm1984_gym` | `hm1984_gym_bare` | `simplified_py` | `simplified_py_bare` | `michell_l15` | `michell_l15_L2basis` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| KCS | 0.108 | 5.23e+06 | 3.796 | 3.953 (-4.1%) | 3.932 (-3.6%) | 3.959 (-4.3%) | 3.938 (-3.7%) | 3.955 (-4.2%) | 3.934 (-3.6%) | 4.075 (-7.3%) | 3.960 (-4.3%) |
| KCS | 0.152 | 7.36e+06 | 3.641 | 3.751 (-3.0%) | 3.744 (-2.8%) | 3.756 (-3.2%) | 3.750 (-3.0%) | 3.732 (-2.5%) | 3.718 (-2.1%) | 4.261 (-17.0%) | 3.800 (-4.4%) |
| KCS | 0.195 | 9.44e+06 | 3.475 | 3.743 (-7.7%) | 3.793 (-9.2%) | 3.743 (-7.7%) | 3.804 (-9.5%) | 3.612 (-4.0%) | 3.618 (-4.1%) | 4.225 (-21.6%) | 3.663 (-5.4%) |
| KCS | 0.227 | 1.10e+07 | 3.467 | 3.876 (-11.8%) | 4.011 (-15.7%) | 3.870 (-11.6%) | 4.027 (-16.1%) | 3.571 (-3.0%) | 3.601 (-3.9%) | 4.524 (-30.5%) | 3.642 (-5.0%) |
| KCS | 0.260 | 1.26e+07 | 3.711 | 4.125 (-11.2%) | 4.381 (-18.0%) | 4.106 (-10.6%) | 4.400 (-18.6%) | 3.564 (+4.0%) | 3.628 (+2.2%) | 4.274 (-15.2%) | 3.532 (+4.8%) |
| KCS | 0.282 | 1.37e+07 | 4.501 | 4.418 (+1.9%) | 4.797 (-6.6%) | 4.390 (+2.5%) | 4.826 (-7.2%) | 3.578 (+20.5%) | 3.669 (+18.5%) | 5.001 (-11.1%) | 3.625 (+19.5%) |
| JBC | 0.142 | 7.44e+06 | 4.289 | 4.488 (-4.6%) | 4.488 (-4.6%) | 4.658 (-8.6%) | 4.658 (-8.6%) | 4.258 (+0.7%) | 4.258 (+0.7%) | 4.916 (-14.6%) | 4.550 (-6.1%) |
| KVLCC2 | 0.142 | 4.60e+06 | 4.110 | 4.828 (-17.5%) | 4.644 (-13.0%) | 4.913 (-19.5%) | 4.739 (-15.3%) | 4.772 (-16.1%) | 4.560 (-10.9%) | 5.236 (-27.4%) | 4.800 (-16.8%) |
| DTMB5415 | 0.100 | 3.91e+06 | 3.930 | 4.192 (-6.7%) | 4.116 (-4.7%) | 4.105 (-4.4%) | 4.025 (-2.4%) | 3.994 (-1.6%) | 3.915 (+0.4%) | 4.187 (-6.6%) | 4.049 (-3.0%) |
| DTMB5415 | 0.280 | 1.09e+07 | 4.193 | 4.446 (-6.0%) | 4.426 (-5.6%) | 4.050 (+3.4%) | 4.064 (+3.1%) | 3.747 (+10.6%) | 3.757 (+10.4%) | 4.865 (-16.0%) | 3.567 (+14.9%) |
| DTMB5415 | 0.410 | 1.60e+07 | 6.460 | 6.566 (-1.6%) | 6.510 (-0.8%) | 6.104 (+5.5%) | 6.163 (+4.6%) | 4.501 (+30.3%) | 4.529 (+29.9%) | 5.835 (+9.7%) | 3.531 (+45.3%) |

## Bulb / transom terms: before → after (E%D)

- KCS: A_BT 0.02934 m², h_B 0.1654 m, A_T 0.0001511 m², C_WP 0.830 (model scale, from Tokyo 2015 KCS_hull_SVA.igs (full scale)).
- JBC: no hull lines → no bulb / transom terms.
- KVLCC2: A_BT 0.05129 m², h_B 0.1766 m, A_T 0 m², C_WP 0.902 (model scale, from Gothenburg 2000 kvlcc2.fix offsets (full scale)).
- DTMB5415: A_BT 0 m², h_B 0 m, A_T 0.004482 m², C_WP 0.774 (model scale, from Gothenburg 2000 5415_static.net (model 5.72 m)).

| hull | Fn | `hm1984_full_bare` → `hm1984_full` | `hm1984_gym_bare` → `hm1984_gym` | `simplified_py_bare` → `simplified_py` |
|---|---|---|---|---|
| KCS | 0.108 | -3.6 → -4.1 | -3.7 → -4.3 | -3.6 → -4.2 |
| KCS | 0.152 | -2.8 → -3.0 | -3.0 → -3.2 | -2.1 → -2.5 |
| KCS | 0.195 | -9.2 → -7.7 | -9.5 → -7.7 | -4.1 → -4.0 |
| KCS | 0.227 | -15.7 → -11.8 | -16.1 → -11.6 | -3.9 → -3.0 |
| KCS | 0.260 | -18.0 → -11.2 | -18.6 → -10.6 | +2.2 → +4.0 |
| KCS | 0.282 | -6.6 → +1.9 | -7.2 → +2.5 | +18.5 → +20.5 |
| JBC | 0.142 | -4.6 → -4.6 | -8.6 → -8.6 | +0.7 → +0.7 |
| KVLCC2 | 0.142 | -13.0 → -17.5 | -15.3 → -19.5 | -10.9 → -16.1 |
| DTMB5415 | 0.100 | -4.7 → -6.7 | -2.4 → -4.4 | +0.4 → -1.6 |
| DTMB5415 | 0.280 | -5.6 → -6.0 | +3.1 → +3.4 | +10.4 → +10.6 |
| DTMB5415 | 0.410 | -0.8 → -1.6 | +4.6 → +5.5 | +29.9 → +30.3 |

## Error by Froude band (mean abs E%)

| oracle | 0.00-0.15 | 0.15-0.22 | 0.22-0.30 | 0.30-0.50 |
|---|---|---|---|---|
| `hm1984_full` | 8.2 (n=4) | 5.4 (n=2) | 7.7 (n=4) | 1.6 (n=1) |
| `hm1984_full_bare` | 6.5 (n=4) | 6.0 (n=2) | 11.5 (n=4) | 0.8 (n=1) |
| `hm1984_gym` | 9.2 (n=4) | 5.4 (n=2) | 7.0 (n=4) | 5.5 (n=1) |
| `hm1984_gym_bare` | 7.5 (n=4) | 6.2 (n=2) | 11.2 (n=4) | 4.6 (n=1) |
| `simplified_py` | 5.7 (n=4) | 3.2 (n=2) | 9.5 (n=4) | 30.3 (n=1) |
| `simplified_py_bare` | 3.9 (n=4) | 3.1 (n=2) | 8.7 (n=4) | 29.9 (n=1) |
| `michell_l15` | 14.0 (n=4) | 19.3 (n=2) | 18.2 (n=4) | 9.7 (n=1) |
| `michell_l15_L2basis` | 7.6 (n=4) | 4.9 (n=2) | 11.1 (n=4) | 45.3 (n=1) |

## Empirical validity envelopes

- `hm1984_full`: Fn [0.1, 0.41], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.227, KCS@Fn=0.260, KVLCC2@Fn=0.142.
- `hm1984_full_bare`: Fn [0.1, 0.41], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.227, KCS@Fn=0.260, KVLCC2@Fn=0.142.
- `hm1984_gym`: Fn [0.1, 0.41], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.227, KCS@Fn=0.260, KVLCC2@Fn=0.142.
- `hm1984_gym_bare`: Fn [0.1, 0.41], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.227, KCS@Fn=0.260, KVLCC2@Fn=0.142.
- `simplified_py`: Fn [0.1, 0.26], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.282, KVLCC2@Fn=0.142, DTMB5415@Fn=0.280, DTMB5415@Fn=0.410.
- `simplified_py_bare`: Fn [0.1, 0.26], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.282, KVLCC2@Fn=0.142, DTMB5415@Fn=0.280, DTMB5415@Fn=0.410.
- `michell_l15`: Fn [0.1, 0.41], Cb [0.507, 0.65], Cp [0.618, 0.66], L_B [7.14, 7.45], B_T [2.98, 3.1], lcb_frac [-0.0148, -0.00683]. Failed: KCS@Fn=0.152, KCS@Fn=0.195, KCS@Fn=0.227, KCS@Fn=0.260, KCS@Fn=0.282, JBC@Fn=0.142, KVLCC2@Fn=0.142, DTMB5415@Fn=0.280.
- `michell_l15_L2basis`: Fn [0.1, 0.26], Cb [0.507, 0.858], Cp [0.618, 0.86], L_B [6.22, 7.45], B_T [2.73, 3.1], lcb_frac [-0.0148, 0.0255]. Failed: KCS@Fn=0.282, KVLCC2@Fn=0.142, DTMB5415@Fn=0.280, DTMB5415@Fn=0.410.

## Empirical drift thresholds (per oracle pair)

| seen | held-out | threshold | pairs | median | max |
|---|---|---|---|---|---|
| `hm1984_gym` | `michell_l15` | 0.144 | 40 | 0.058 | 0.149 |
| `hm1984_gym` | `simplified_py` | 0.095 | 40 | 0.042 | 0.108 |
| `hm1984_gym` | `hm1984_full` | 0.090 | 40 | 0.022 | 0.093 |
| `simplified_py` | `michell_l15` | 0.122 | 40 | 0.064 | 0.125 |
| `hm1984_gym_bare` | `michell_l15` | 0.180 | 40 | 0.067 | 0.225 |
| `hm1984_gym_bare` | `simplified_py_bare` | 0.137 | 40 | 0.049 | 0.184 |
| `hm1984_gym_bare` | `hm1984_full_bare` | 0.092 | 40 | 0.023 | 0.093 |
| `simplified_py_bare` | `michell_l15` | 0.122 | 40 | 0.056 | 0.127 |

Method: quantile of |Δe_seen − Δe_holdout| over reference-point pairs (first-order error propagation); |ΔFn| <= 0.06, q = 0.95. Pairs span different hulls, so this is an upper-end estimate for the small parent→child steps a search takes; the same-hull-only variant (KCS speed pairs) is in the JSON under `drift_thresholds_same_hull`.

## Caveats

Validation of this harness's oracles against public tank data. Small sample (11 points, 4 hulls): treat envelopes as evidence bounds, not certified validity ranges. Not ITTC V&V, not class.
- Bulb / transom / C_WP come from the real hull lines (KCS, KVLCC2, 5415); JBC has no lines here, so its `hm1984_full` uses the Schneekluth C_WP and no bulb.
- `michell_l15` uses the gym's synthetic Wigley-like offsets, not the real hull lines.
- Low-Fn points (Fn ≈ 0.1) carry larger tank uncertainty (3.2% for 5415).
