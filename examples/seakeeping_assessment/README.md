# Seakeeping Assessment Example

End-to-end composition workflow: ITTC modified PM spectrum → strip-theory
heave RAO → response spectral moments → Fossen RK4 operability check.

**Proof level:** `unit-tested`  
**Oracle:** `yard-seakeeping-oracle-v0.1`  
**Workflow:** `compose/seakeeping_assessment.zig`

## Run

From repo root:

```sh
zig build run-seakeeping
zig build test-core
```

From this directory:

```sh
zig build run
zig build test
```

## Expected (canonical case)

| Quantity | Value |
|----------|-------|
| L × B × T | 100 × 16 × 6 m |
| Sea state | Hs=2.0 m, Tz=8.0 s |
| Significant heave | ~5.74 m |
| Peak RAO | ~14.6 m/m @ ω≈1.2 rad/s |
| Operability | FAIL (max heave ~10.9 m > 2.0 m limit) |

## Intelligence pipeline

```sh
python tools/dataset/generate_seakeeping.py --samples 200 --output tools/dataset/out/seakeeping_train.jsonl
python tools/agent/harness.py --workflow seakeeping
python tools/gap_audit/gap_audit_seakeeping.py --dataset tools/dataset/out/seakeeping_eval.jsonl --baseline naive
```

License: Apache-2.0.