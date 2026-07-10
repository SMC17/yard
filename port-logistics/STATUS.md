# Status

yard-port-logistics-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2. 37/37 tests pass.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `throughput` | `unit-tested` | berth-hours × moves/hr; quay-metre normalisation |
| `dwell` | `unit-tested` | Little's Law; weighted dwell; yard slot count |
| `truck` | `unit-tested` | Erlang-C M/M/c wait; time-of-day peak factor |

Evaluation logic `unit-tested`. UNCTAD utilisation band and
stack-density rules of thumb caller-supplied.