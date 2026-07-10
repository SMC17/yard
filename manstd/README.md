# manstd

IMO ship manoeuvrability standards + Nomoto prediction.

- **criteria** — IMO Resolution MSC.137(76) encoded exactly: turning
  (advance <= 4.5L, tactical diameter <= 5L), initial turning (<= 2.5L at
  10 deg heading change with 10 deg rudder), 10/10 and 20/20 zig-zag
  overshoot limits including the piecewise L/V bands, stopping track
  reach (<= 15L). Trial-report in, per-criterion pass/fail out.
- **nomoto** — first-order Nomoto model (T r' + r = K delta), RK4 at fixed
  step with finite rudder slew: steady turning diameter from K', full
  zig-zag simulation predicting first/second overshoot from (K', T').
  Property-tested: overshoot grows with T' (sluggishness) and K' (rudder
  power); diameter scales as 2L/(K' delta).

Together: predict IMO compliance at preliminary design, before the model
basin. Sources: IMO MSC.137(76) + explanatory notes MSC/Circ.1053;
Nomoto (1957). Zero dependencies.

Proof level: unit-tested (resolution numbers exact, integrator
property-tested).
