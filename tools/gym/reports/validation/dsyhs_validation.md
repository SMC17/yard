# Oracle check on the Delft Systematic Yacht Hull Series (out-of-population set)

Schema `yard_sea_v0.validation.dsyhs.v1`. 500 measured points on 36 canoe bodies, Fn 0.09–0.75. Source: DSYHS (TU Delft, 4TU.ResearchData doi:10.4121/21501375 + 10.4121/21501402), CC0; model scale.

Convention: E%D = (D - S)/D*100 with C_T on canoe-body wetted area S_c; C_F ITTC-57 at tank Re; no C_A.

| oracle | n | mean E% | median abs E% | p90 abs E% | share within ±10% |
|---|---|---|---|---|---|
| `hm1984_full` | 500 | -1.6 | 17.2 | 43.5 | 24% |
| `hm1984_gym_bare` | 500 | +3.3 | 19.1 | 56.2 | 21% |
| `simplified_py_bare` | 500 | +32.4 | 27.2 | 82.5 | 25% |
| `michell_l15` | 500 | -46.5 | 36.5 | 106.1 | 24% |

## By Froude band (median abs E%)

| oracle | 0.0-0.2 | 0.2-0.3 | 0.3-0.4 | 0.4-0.5 | 0.5-0.8 |
|---|---|---|---|---|---|
| `hm1984_full` | 19.6 (n=113) | 10.8 (n=60) | 12.7 (n=90) | 11.9 (n=80) | 25.5 (n=157) |
| `hm1984_gym_bare` | 19.4 (n=113) | 10.9 (n=60) | 12.7 (n=90) | 11.7 (n=80) | 38.4 (n=157) |
| `simplified_py_bare` | 7.3 (n=113) | 12.6 (n=60) | 31.9 (n=90) | 65.5 (n=80) | 72.3 (n=157) |
| `michell_l15` | 51.1 (n=113) | 75.7 (n=60) | 55.4 (n=90) | 43.2 (n=80) | 6.8 (n=157) |

## Does the applicability check separate good from bad predictions?

Share of DSYHS points inside the HM declared range: 0%; inside the tank-validated envelope: 0%.

| oracle | declared range: inside | outside | tank envelope: inside | outside |
|---|---|---|---|---|
| `hm1984_full` | – | 17.2% (n=500) | – | 17.2% (n=500) |
| `hm1984_gym_bare` | – | 19.1% (n=500) | – | 19.1% (n=500) |
| `simplified_py_bare` | – | 27.2% (n=500) | – | 27.2% (n=500) |
| `michell_l15` | – | 36.5% (n=500) | – | 36.5% (n=500) |

## Gym wetted-area approximation on yachts

`HullState.wetted_approx()` / measured S_c: median 1.71, range 1.55–1.91. The validation assembles C_T with the measured S_c; the gym itself uses its approximation.

## Caveats

- Holtrop-Mennen and the gym's simplified model were built for ships, not yacht canoe bodies: this is an out-of-population check, not a calibration. Results are not used in rewards.
- Models without a recorded water temperature (Sys 24, 28, 42–46, 48) are skipped rather than assuming a temperature.
- Fn above ~0.45 involves large sinkage / trim (recorded in the source, not modelled by any L1 oracle).
