# KVLCC2: HM1984 bulb inputs and why the bulb term worsens the error

Model-scale tank point Fn 0.142, measured C_T 0.00411. E% = (D - S)/D (negative = over-prediction).

## Inputs (full scale)

| input | lines-derived (yard) | published | diff |
|---|---|---|---|
| A_BT [m²] | 172.6 | 174.03 | -0.8% |
| h_B [m] | 10.24 | 10.28 | -0.4% |
| A_T [m²] | 0.0 (transom flag off: stern offsets truncated) | 13.82 | – |
| T_F [m] | 20.8 (even keel, T_F = T) | 20.8 | 0 |

Published source: Chahbi (2014), EMSHIP master thesis, KVLCC2, Table 2 (TRIBON M3 Holtrop-Mennen inputs).

## hm1984_full with each input set

| inputs | C_T pred | E% | C_F(1+k) | 1+k | C_W | C_bulb | C_tr | c_2 |
|---|---|---|---|---|---|---|---|---|
| bare (no bulb, no transom) | 0.00465 | -13.2 | 0.00456 | 1.322 | 9.00e-05 | 0.00e+00 | 0.00e+00 | 1.000 |
| lines-derived bulb (current) | 0.00483 | -17.5 | 0.00456 | 1.322 | 5.42e-05 | 2.13e-04 | 0.00e+00 | 0.602 |
| published bulb (Chahbi 2014) | 0.00484 | -17.8 | 0.00456 | 1.322 | 5.40e-05 | 2.27e-04 | 0.00e+00 | 0.600 |
| published bulb + transom (Chahbi 2014) | 0.00484 | -17.8 | 0.00456 | 1.322 | 5.35e-05 | 2.27e-04 | 0.00e+00 | 0.600 |

## Finding

- The lines-derived bulb inputs agree with the independent published set to within 1% (A_BT) and 0.5% (h_B); T_F = T is correct for the even-keel design condition. **No input is wrong, so nothing is changed.**
- In HM1984 a large bulb (A_BT ≈ 14% of the midship area) on a slow full ship adds R_B ≈ 4x the whole wave term, while c_2 can only remove part of an already small C_W: the regression itself makes the bulb net-adverse at Fn 0.14.
- The error is dominated by the viscous term: C_F(1+k) alone already exceeds the measured C_T. Even with zero wave resistance, matching the measurement would need 1+k <= C_T/C_F = 1.191, against HM's 1.322. Fixing the bulb would not fix KVLCC2.
- Adding the published transom area (the yard lines have none because the stern offsets are truncated) changes nothing at this speed: F_nT >= 5 so c_6 = 0 and R_TR = 0, and c_5 moves C_W by < 1%.
