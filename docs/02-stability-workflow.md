# Stability Workflow Deep Dive

## Problem Statement

Given principal dimensions, tank geometry, and loading for a floating box-barge:

1. Compute hydrostatics (KB, BM_T, KM_T)
2. Compute GM₀ and apply rectangular-tank free-surface correction
3. Build wall-sided GZ curve (Atwood formula)
4. Evaluate six IMO IS Code 2008 Part A 2.2 criteria
5. Return structured pass/fail + margins + assumption flags

## Formula Chain

### Hydrostatics (closed form, rectangular)

```
V     = L · B · T
KB    = T / 2
I_T   = L · B³ / 12
BM_T  = I_T / V = B² / (12T)
KM_T  = KB + BM_T
```

### Metacentric height

```
GM₀ = KM_T − KG
```

### Free-surface correction (per rectangular tank)

```
i_FS = (1/12) · l · b³
GG'ᵢ = (ρ_fluid / ρ_seawater) · i_FS / V
GG'_total = Σ GG'ᵢ
GM_corrected = GM₀ − GG'_total
```

### Wall-sided GZ (Atwood)

Valid when B/(2T) > 1 and heel angle within envelope (~≤25°):

```
GZ(φ) = (GM + ½ · BM_T · tan²φ) · sinφ
```

Small-angle fallback: `GZ(φ) = GM · sinφ`

### IMO IS Code 2008 Part A 2.2 thresholds

| Criterion | Threshold |
|-----------|-----------|
| Area under GZ, 0°–30° | ≥ 0.055 m·rad |
| Area under GZ, 0°–40° | ≥ 0.090 m·rad |
| Area under GZ, 30°–40° | ≥ 0.030 m·rad |
| GZ at heel ≥ 30° | ≥ 0.200 m |
| Angle of maximum GZ | ≥ 25° |
| GM₀ | ≥ 0.150 m |

Areas computed by trapezoidal integration over supplied GZ samples.

## Canonical Validation Case

From Biran & Lopez-Pulido (2013) Ch.10 and `validation_fixtures.md` §2:

| Parameter | Value |
|-----------|-------|
| L × B × T | 10 × 4 × 1.5 m |
| KG | 1.0 m |
| Tank | 5 × 3 m fresh water |
| V | 60 m³ |
| KM_T | 1.6389 m |
| GM₀ | 0.6389 m |
| GG' | ~0.183 m |
| GM corrected | ~0.456 m |
| GZ at 10° | ~0.1134 m |

## Code Map

| Step | Zig module | File |
|------|------------|------|
| Hydrostatics | `hydro` | `hydro/src/box_barge.zig` |
| GZ + FS | `stability` | `stability/src/gz.zig` |
| IS Code | `stability` | `stability/src/is_code.zig` |
| Composition | `compose` | `compose/src/box_barge.zig` |
| Oracle | Python | `tools/oracle/yard_stability_oracle.py` |

## Where Frontier Models Fail

Document these in gap-audit before fine-tuning:

- Omit free-surface correction entirely
- Use small-angle GZ when wall-sided is required
- Wrong i_FS formula (forget 1/12 or b³)
- Apply IS Code thresholds to uncorrected GM
- Confident answers outside validity envelope
- Subtle ρ or unit errors (permille level)

## Run

```sh
zig build run-example
python tools/oracle/yard_stability_oracle.py
```