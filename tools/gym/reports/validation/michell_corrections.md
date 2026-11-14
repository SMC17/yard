# Michell on real hull lines: published viscous / transom corrections

E% = (D - S)/D (negative = over-prediction). Model scale, ITTC-57 C_F at tank Re. Validation tolerance ±10% (the harness default).

## Summary

| variant | n | mean E% | mean abs E% | max abs E% | within tol |
|---|---|---|---|---|---|
| baseline (HM 1+k, open stern) | 10 | -63.1 | 63.1 | 128.7 | 1/10 |
| Watanabe 1+k | 10 | -57.3 | 57.3 | 124.0 | 1/10 |
| HM 1+k + transom (Doctors appendage + HM R_TR) | 10 | -56.4 | 56.4 | 129.0 | 1/10 |
| Watanabe 1+k + transom | 10 | -50.6 | 50.6 | 124.3 | 2/10 |

## Per point (C_T x10^3, E%)

| hull | Fn | meas | baseline (HM 1+k, open stern) | Watanabe 1+k | HM 1+k + transom (Doctors appendage + HM R_TR) | Watanabe 1+k + transom | 1+k HM / Wat. | C_W/S0 open / +app. |
|---|---|---|---|---|---|---|---|---|
| KCS | 0.108 | 3.796 | 4.041 (-6.5%) | 3.791 (+0.1%) | 4.059 (-6.9%) | 3.809 (-0.3%) | 1.168 / 1.094 | 1.06e-04 / 1.24e-04 |
| KCS | 0.152 | 3.641 | 4.315 (-18.5%) | 4.080 (-12.1%) | 4.348 (-19.4%) | 4.113 (-13.0%) | 1.168 / 1.094 | 6.16e-04 / 6.49e-04 |
| KCS | 0.195 | 3.475 | 5.057 (-45.5%) | 4.832 (-39.0%) | 5.094 (-46.6%) | 4.869 (-40.1%) | 1.168 / 1.094 | 1.52e-03 / 1.55e-03 |
| KCS | 0.227 | 3.467 | 6.103 (-76.0%) | 5.884 (-69.7%) | 6.139 (-77.1%) | 5.920 (-70.8%) | 1.168 / 1.094 | 2.66e-03 / 2.69e-03 |
| KCS | 0.260 | 3.711 | 6.985 (-88.2%) | 6.771 (-82.5%) | 7.013 (-89.0%) | 6.799 (-83.2%) | 1.168 / 1.094 | 3.62e-03 / 3.64e-03 |
| KCS | 0.282 | 4.501 | 10.293 (-128.7%) | 10.082 (-124.0%) | 10.308 (-129.0%) | 10.097 (-124.3%) | 1.168 / 1.094 | 6.97e-03 / 6.99e-03 |
| KVLCC2 | 0.142 | 4.110 | 8.697 (-111.6%) | 8.586 (-108.9%) | 8.697 (-111.6%) | 8.586 (-108.9%) | 1.345 / 1.313 | 4.06e-03 / 4.06e-03 |
| DTMB5415 | 0.100 | 3.930 | 8.135 (-107.0%) | 7.801 (-98.5%) | 5.681 (-44.5%) | 5.347 (-36.0%) | 1.132 / 1.038 | 4.11e-03 / 1.54e-03 |
| DTMB5415 | 0.280 | 4.193 | 5.179 (-23.5%) | 4.902 (-16.9%) | 4.857 (-15.8%) | 4.580 (-9.2%) | 1.132 / 1.038 | 1.84e-03 / 1.51e-03 |
| DTMB5415 | 0.410 | 6.460 | 8.125 (-25.8%) | 7.865 (-21.8%) | 7.988 (-23.7%) | 7.728 (-19.6%) | 1.132 / 1.038 | 4.99e-03 / 4.85e-03 |

## Transom inputs (model scale, from the lines)

| hull | Fn | A_T m² | T_T m | F_nT | hollow m | c_6 | C_TR |
|---|---|---|---|---|---|---|---|
| KCS | 0.108 | 2.01e-04 | 0.0000 | n/a (T_T below grid) | 0.000 | 0.000 | 0.00e+00 |
| KCS | 0.152 | 2.01e-04 | 0.0000 | n/a (T_T below grid) | 0.000 | 0.000 | 0.00e+00 |
| KCS | 0.195 | 2.01e-04 | 0.0000 | n/a (T_T below grid) | 0.000 | 0.000 | 0.00e+00 |
| KCS | 0.227 | 2.01e-04 | 0.0000 | n/a (T_T below grid) | 0.000 | 0.000 | 0.00e+00 |
| KCS | 0.260 | 2.01e-04 | 0.0000 | n/a (T_T below grid) | 0.000 | 0.000 | 0.00e+00 |
| KCS | 0.282 | 2.01e-04 | 0.0000 | n/a (T_T below grid) | 0.000 | 0.000 | 0.00e+00 |
| DTMB5415 | 0.100 | 4.35e-03 | 0.0185 | 1.76 | 0.123 | 0.130 | 1.17e-04 |
| DTMB5415 | 0.280 | 4.35e-03 | 0.0185 | 4.93 | 0.123 | 0.003 | 2.68e-06 |
| DTMB5415 | 0.410 | 4.35e-03 | 0.0185 | 7.21 | 0.123 | 0.000 | 0.00e+00 |

## Sensitivity

| case | change | E% | C_W/S0 |
|---|---|---|---|
| KVLCC2@Fn=0.142 | truncated stern closed as if a transom | -120.8 | 4.46e-03 |
| DTMB5415@Fn=0.100 | hollow length x0.5 | -49.3 | 2.06e-03 |
| DTMB5415@Fn=0.100 | hollow length x2.0 | -29.9 | 1.30e-03 |
| DTMB5415@Fn=0.280 | hollow length x0.5 | -12.6 | 1.65e-03 |
| DTMB5415@Fn=0.280 | hollow length x2.0 | -6.2 | 1.38e-03 |
| DTMB5415@Fn=0.410 | hollow length x0.5 | -20.7 | 4.92e-03 |
| DTMB5415@Fn=0.410 | hollow length x2.0 | -18.3 | 4.77e-03 |

## Finding

- Mean |E| goes from 63.1% (baseline) to 50.6% (Watanabe 1+k + transom); 2/10 points are within ±10%.
- The corrections act on the wrong term. The residual is Michell's own over-prediction of R_W on blunt real hull forms (C_W/S0 alone is about the size of the measured C_T at KCS Fn 0.26, KVLCC2 and 5415 Fn 0.10). A form factor only moves the viscous term by a few percent, and the transom appendage only helps 5415 at low speed.
- **Not validated, so no envelope is set.** `michell_lines` stays without an applicability envelope on real hull forms, and the corrections are exposed here as a study, not as a gym oracle.

Conventions: hollow_length: 6.68 T_T (Doctors 2006 minimum; full regression not used); transom_section: 0.002 Lpp inside aft end (hull_lines A_T convention); grid: open stern {'nx': 121, 'nz': 31, 'n_theta': 60}, transom variants {'nx': 481, 'nz': 61, 'n_theta': 60}; appendage_depth: T_T (1 - s)^2 parabola (Doctors hollow shape); transom_drag: HM1984 c_6 (wet/partially ventilated); Doctors-Day dry hydrostatic not used.
