# Box-Barge Intact Stability Example

End-to-end composition workflow: hydrostatics → GM + free-surface correction →
wall-sided GZ curve → IMO IS Code 2008 Part A 2.2 evaluation.

**Proof level:** `unit-tested`  
**Reference:** Biran & Lopez-Pulido (2013) Ch.10 box-barge; `validation_fixtures.md` §2

## Run

```sh
zig build run
zig build run -- --envelope
zig build run -- --case coastal-feeder --envelope
zig build run -- --L 11 --B 4 --T 1.5 --KG 1.0 --envelope
zig build run -- --no-tank --envelope
zig build test
```

### Flags

| Flag | Meaning |
|------|---------|
| `--case canonical\|coastal-feeder` | Named hull/loading (default: canonical) |
| `--L/--B/--T/--KG` | Override particulars / loading (metres) |
| `--tank LxB[@rho]` | Rectangular FS tank (`rho` default 1000) |
| `--no-tank` | Clear tanks |
| `--envelope` | Emit ArtifactEnvelope JSON (includes `case_id` + live particulars) |

## Cases

| Case | L × B × T | KG | Tank |
|------|-----------|----|------|
| `canonical` | 10 × 4 × 1.5 m | 1.0 m | 5 × 3 m fresh water |
| `coastal-feeder` | 24 × 8 × 2.5 m | 1.8 m | 8 × 4 m fresh water |

## Expected (canonical)

| Quantity | Value |
|----------|-------|
| GM₀ | ~0.639 m |
| GG' | ~0.183 m |
| GM corrected | ~0.456 m |
| GZ at 10° | ~0.113 m |

License: Apache-2.0.
