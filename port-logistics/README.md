# yard-port-logistics-zig

Proof level: `unit-tested`

Port-logistics kernel: annual throughput from berth/gate primitives; container
dwell time + yard slot requirement; truck-gate Erlang-C queueing + time-of-day
demand multiplier.

## What it does

- `throughput` — annual TEU from N berths × hours × crane mph; effective berth
  hours from utilisation + downtime; moves-per-hour with dual-cycling and loss;
  TEU per quay metre.
- `dwell` — Little's Law N = λ t_dwell; yard slots = N / density; weighted
  dwell for import / export / transship mix; annual moves per ground slot.
- `truck` — Erlang-C wait probability + average wait + queue length;
  triangle-peak time-of-day multiplier (max 2.0 at peak).

## What it is not

Not a discrete-event port simulation, berth-allocation optimizer, or hinterland
transport model. Throughput and dwell estimates are steady-state accounting —
not demand forecasting, tariff modelling, or carbon-footprint reporting. Not
integrated with `yard-terminal-zig` crane physics in a single live TOS workflow.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 37/37 tests passed`.

## References

- UNCTAD (2020). *Review of Maritime Transport*.
- Bichou, K. (2014). *Port Operations, Planning and Logistics*.
- Erlang, A. K. (1917). *Solution of some Problems in the Theory of
  Probabilities of Significance in Automatic Telephone Exchanges*. Post Office
  Electrical Engineers' Journal.
- Little, J. D. C. (1961). *A Proof for the Queuing Formula L = λ W*.
  Operations Research 9.

## License

Apache-2.0. See `LICENSE`.