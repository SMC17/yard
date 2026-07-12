# Box-Barge Intact Stability Example

End-to-end composition workflow: hydrostatics → GM + free-surface correction →
wall-sided GZ curve → IMO IS Code 2008 Part A 2.2 evaluation.

**Proof level:** `unit-tested`  
**Reference:** Biran & Lopez-Pulido (2013) Ch.10 box-barge; `validation_fixtures.md` §2

## Run

```sh
zig build run
zig build run -- --envelope   # ArtifactEnvelope JSON for Sovereign Experience
zig build test
```

## Expected (canonical case)

| Quantity | Value |
|----------|-------|
| L × B × T | 10 × 4 × 1.5 m |
| KG | 1.0 m |
| Tank | 5 × 3 m fresh water |
| GM₀ | ~0.639 m |
| GG' | ~0.183 m |
| GM corrected | ~0.456 m |
| GZ at 10° | ~0.113 m |

License: Apache-2.0.