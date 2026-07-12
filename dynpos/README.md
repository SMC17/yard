# yard-dynpos-zig

Proof level: `unit-tested`

yard-dynpos-zig is a Zig 0.16 dynamic-positioning thruster-allocation
kernel for 3-DOF (surge / sway / yaw) demand on a fixed-direction
multi-thruster vessel. Minimum-energy pseudo-inverse allocation
`u = B^T (B B^T)^(-1) tau` with up to eight thrusters, singular-
configuration detection, and a closing-residual diagnostic.

## What it does

- `allocation.Thruster` typed struct (alpha_rad, x_m, y_m).
- `allocation.Demand` typed struct (X_n, Y_n, N_nm).
- `allocation.allocate(thrusters, tau, u_out)` computes the minimum-
  energy thrust vector for an N x 3 configuration matrix `B`.
- `allocation.closingResidual(thrusters, u, tau)` returns the
  Euclidean distance between the actual applied force/moment and
  the demand.
- `allocation.max_thrusters = 8` stack-buffer ceiling.

## What it is not (v0.0.0)

- No azimuthing-thruster steering-angle optimisation (the thrust
  directions `alpha_i` are inputs, not decision variables).
- No saturation / thrust-limit handling (caller checks `|u[i]| <=
  T_max_i` externally).
- No power-management / blackout reconfiguration.
- No DP-2 / DP-3 redundancy class selection (the kernel allocates
  on a given configuration; failure-tolerant reconfiguration is the
  next layer).
- No wave / wind feedforward (this is the steady-state allocation
  primitive).
- No quadratic-programming solver (compose with an external QP
  library when thrust constraints become binding).

## Build and test

```
zig build test --summary all
```

Expected: `Build Summary: 3/3 steps succeeded; 15/15 tests passed`.

## ArmadaClaw telemetry bridge

`telemetry_protocol` defines the strict `yard.telemetry.v1` state and thruster
command envelopes shared with the Elixir/OTP coordinator. `nats_telemetry`
publishes state frames to `yard.telemetry.v1.state`, performs the NATS CONNECT
handshake, handles partial writes, and waits for a PONG flush before close.

With a local NATS broker and ArmadaClaw process running:

```sh
zig build telemetry-publish -- 100
zig build telemetry-roundtrip -- 100
```

The first command publishes ordered state frames. The second subscribes before
publishing and requires one strict `thruster_command` response for each state
sequence, providing a closed Zig -> NATS -> ArmadaClaw -> NATS -> Zig protocol
check.

## Public API

```zig
const yard = @import("yard_dynpos");

const thr = [_]yard.allocation.Thruster{
    .{ .alpha_rad = std.math.pi / 2.0, .x_m = 50.0, .y_m = 0.0 },
    .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = 10.0 },
    .{ .alpha_rad = 0.0, .x_m = -50.0, .y_m = -10.0 },
};
var u: [3]f64 = undefined;
try yard.allocation.allocate(&thr,
    .{ .X_n = 10_000.0, .Y_n = 0.0, .N_nm = 0.0 }, &u);
const r = try yard.allocation.closingResidual(&thr, &u, /* tau */);
```

## Validation

- Three-thruster bow + two stern allocation closes within 1 N for
  10 000 N pure surge demand.
- Pure-surge demand on bow-tunnel + stern-pod system leaves bow
  tunnel inactive in the minimum-energy sense.
- Stern pods split surge symmetrically (5 000 N each).
- Pure-yaw demand differential-loads the stern pods by
  `2 |y_pod| Delta u = N_demand`.
- Bow-tunnel + canted-stern-pod allocation closes within 1 N for
  9 000 N pure sway demand.
- Four-thruster DP-2-style redundant configuration closes within
  1 N for a combined (X, Y, N) demand.
- Degenerate configuration (all colinear longitudinal thrusters)
  returns `Error.SingularConfigurationMatrix`.
- Typed-error rejection for empty thruster list.
- Strict state-envelope encoding and thruster-command parsing for
  `yard.telemetry.v1`.
- Exact NATS PUB header length, subject validation, payload ceiling, and
  broker-flush behavior.
- NATS command subscription, payload framing, strict parse, and ordered
  telemetry-sequence correlation.

## Constraint inheritance

Per `~/CONVENTIONS.md` C2: bound by Zig 0.16 (pre-1.0).

## References

- Fossen, T. I. (2011). *Handbook of Marine Craft Hydrodynamics and
  Motion Control*. Wiley.
- Snijders, J. G., van der Klugt, P. G. M., Quadvlieg, F. H. H. A.
  (2005). *Thrust allocation for the dynamic positioning of marine
  vessels*. CAMS.
- IMCA M 103. *Guidelines for the design and operation of dynamically
  positioned vessels*.
- IMO MSC.1/Circ.1580. *Guidelines for vessels and units with
  dynamic positioning (DP) systems*.

## License

Apache-2.0.
