# yard-terminal-zig

Proof level: `unit-tested`

Container-terminal operations kernel: berth allocation + service
time; truck-gate M/M/c queueing; STS crane productivity with
dual-cycling and multi-crane interference.

## Modules

- `berth` — per-vessel service time, berth utilisation, annual
  capacity, UNCTAD 0.55-0.70 sweet-spot verdict.
- `gate` — server utilisation, M/M/1 wait and queue-length, M/M/c
  approximate wait (upper-bound), throughput.
- `crane` — net moves-per-hour with dual-cycling uplift and
  loss-fraction; multi-crane interference efficiency; vessel
  total moves rate.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 43/43 tests passed`.

## References

- UNCTAD (2004). *Assessment of a Seaport Land Interface*.
- Bichou, K. (2014). *Port Operations, Planning and Logistics*.
- Goodchild, A. V., Daganzo, C. F. (2005). *Crane Double Cycling
  in Container Ports*. UC Berkeley Tech Report.

Apache-2.0.
