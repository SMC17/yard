# econ

Voyage economics for the Yard Trials: annual-cashflow ship economics in
closed form.

- **Capital**: capex amortized by the capital recovery factor
  `CRF = r(1+r)^n / ((1+r)^n - 1)` (straight-line at zero interest).
- **Opex**: crew, maintenance and hull & machinery insurance as capex
  fractions, plus an **expected-loss premium** taken directly from the
  mission Monte Carlo loss rate (`voyages x loss_rate x capex`) — risk
  priced as expectation, no actuarial pretence.
- **Voyage costs**: energy (zero for pure sail — wind assist literally pays)
  and port dues.
- **Outputs**: voyages/year, delivered cargo, profit, and **Required Freight
  Rate** (cost per delivered tonne at break-even) — the canonical
  ship-economics figure of merit, and the natural mission objective for
  merchant Trials rungs.

Inputs are plain numbers, so any voyage model sits upstream (mission
runner, sail polars, historical scenarios). Zero dependencies.

Proof level: unit-tested (closed-form finance math, exact).
