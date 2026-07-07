# yard-shipyard-mgmt-zig

Proof level: `unit-tested`

yard-shipyard-mgmt-zig is a Zig 0.16 shipyard production-scheduling
kernel. Three modules: `cpm` for Critical Path Method forward / backward
passes and total-float computation; `pert` for beta-PERT three-point
estimation and project-completion Gaussian statistics; `resource` for
the resource-loading histogram, peak / average load, and smoothness
ratio.

## What it does

### Critical Path Method

- `cpm.Activity` typed struct (duration_days).
- `cpm.Edge` predecessor / successor edge.
- `cpm.forwardPass(activities, edges, topo, es, ef)` computes
  earliest start / finish.
- `cpm.projectFinish(ef)` returns max(EF).
- `cpm.backwardPass(activities, edges, topo, T_finish, ls, lf)`
  latest start / finish.
- `cpm.totalFloat(es, ls, tf)` returns LS - ES per activity.

### PERT three-point

- `pert.Triple` (a, m, b) optimistic / most-likely / pessimistic.
- `pert.mean(t)` returns `(a + 4 m + b) / 6`.
- `pert.standardDeviation(t)` returns `(b - a) / 6`.
- `pert.variance(t)` returns sigma^2.
- `pert.projectMean(criticals)` sum of critical-path means.
- `pert.projectVariance(criticals)` sum of critical-path variances.
- `pert.zScore(T, mu, sigma)` Gaussian Z-score for a target finish.

### Resource loading

- `resource.ResourceWindow` per-activity start / duration / rate.
- `resource.buildHistogram(activities, horizon, hist)` summed per-day
  rate across active activities.
- `resource.peakLoad(hist)`, `averageLoad(hist)`,
  `totalResourceDays(hist)`, `smoothnessRatio(hist)`.

## What it is not (v0.0.0)

- No Monte-Carlo simulation of the critical path.
- No resource-constrained scheduling (RCPSP) solver.
- No earned-value / cost integration.
- No multi-mode activity (alternative resource / duration trade).
- No risk-register / probabilistic-criticality lookup.
- No allocator-based dynamic graph; caller pre-allocates topological
  order and buffers.

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 32/32 tests passed`.

## Public API

```zig
const yard = @import("yard_shipyard_mgmt");

const acts = [_]yard.cpm.Activity{
    .{ .duration_days = 2.0 },
    .{ .duration_days = 5.0 },
    .{ .duration_days = 3.0 },
    .{ .duration_days = 4.0 },
};
const edges = [_]yard.cpm.Edge{
    .{ .from = 0, .to = 1 }, .{ .from = 0, .to = 2 },
    .{ .from = 1, .to = 3 }, .{ .from = 2, .to = 3 },
};
const topo = [_]usize{ 0, 1, 2, 3 };
var es: [4]f64 = undefined;
var ef: [4]f64 = undefined;
try yard.cpm.forwardPass(&acts, &edges, &topo, &es, &ef);
const T = yard.cpm.projectFinish(&ef);

var ls: [4]f64 = undefined;
var lf: [4]f64 = undefined;
try yard.cpm.backwardPass(&acts, &edges, &topo, T, &ls, &lf);
var tf: [4]f64 = undefined;
try yard.cpm.totalFloat(&es, &ls, &tf);
```

## Validation

- Single-activity network: project finish equals duration.
- Linear chain A -> B -> C: ES values accumulate.
- Diamond network: D starts after slower of B / C; total = 11 days.
- Backward pass on linear chain leaves zero float.
- Diamond network: C has 2-day float; A / B / D critical.
- Empty network rejected; negative duration rejected.
- PERT mean closed form at a=2, m=4, b=12 = 5.
- PERT sigma at a=2, b=14 = 2; zero when a = b.
- Variance = sigma^2; project mean = sum of critical means;
  project variance = sum of critical variances.
- Z-score: T at mu = 0; T = mu + 2 sigma = +2.
- Invalid triple ordering rejected (a > m or m > b).
- Resource histogram: single activity loads 5 days at 10 men/day.
- Overlap: 18 peak; 9 average over 10-day horizon.
- Smoothness ratio average / peak = 0.5 in overlap; 1.0 for
  uniform.
- Activity extending past horizon rejected.
- Typed-error rejection for empty histogram, negative rate, invalid
  buffer sizes.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Kelley, J. E., Walker, M. R. (1959). *Critical-Path Planning and
  Scheduling*. Proc. Eastern Joint Computer Conference.
- Malcolm, D. G., Roseboom, J. H., Clark, C. E., Fazar, W. (1959).
  *Application of a Technique for Research and Development Program
  Evaluation*. Operations Research 7.
- Hillier, F. S., Lieberman, G. J. (2014). *Introduction to
  Operations Research*. 10th ed., McGraw-Hill.
- Storch, R. L., Hammon, C. P., Bunch, H. M., Moore, R. C. (1995).
  *Ship Production*. 2nd ed., SNAME.

## License

AGPL-3.0-or-later.
