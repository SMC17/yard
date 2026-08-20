# NEXT — ais (hub harvest)

Harvested unique work from `yard-ais-zig` `a5fcda8` into
`ais/src/nats_telemetry.zig` (2026-08-20). Satellite renamed the duplicate
`publishPrint` that fabricates yacht stats to
`publishFabricatedYachtStatsDoNotUse`. File is still not in `build.zig`
(root.zig tree only). Do not wire the fabricated publisher into any build.

Committed as harvest-only: `nats_telemetry.zig` is not imported by
`src/root.zig` and is not in the test graph (`zig build test` covers
armor/nmea/message1 only). Keep it unwired. Next: a compile-fail or
do-not-use test only if this file is ever imported.
