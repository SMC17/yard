# yard-port-logistics-zig

Proof level: `unit-tested`

Port-logistics kernel: annual throughput from berth/gate primitives;
container dwell time + yard slot requirement; truck-gate Erlang-C
queueing + time-of-day demand multiplier.

## Modules

- `throughput` — annual TEU from N berths * hours * crane mph;
  effective berth hours from utilisation + downtime; moves-per-hour
  with dual-cycling and loss; TEU per quay metre.
- `dwell` — Little's Law N = lambda t_dwell; yard slots = N /
  density; weighted dwell for import / export / transship mix;
  annual moves per ground slot.
- `truck` — Erlang-C wait probability + average wait + queue
  length; triangle-peak time-of-day multiplier (max 2.0 at peak).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 37/37 tests passed`.

## References

- UNCTAD (2020). *Review of Maritime Transport*.
- Bichou, K. (2014). *Port Operations, Planning and Logistics*.
- Erlang, A. K. (1917). *Solution of some Problems in the Theory
  of Probabilities of Significance in Automatic Telephone
  Exchanges*. Post Office Electrical Engineers' Journal.
- Little, J. D. C. (1961). *A Proof for the Queuing Formula
  L = lambda W*. Operations Research 9.

AGPL-3.0-or-later.
