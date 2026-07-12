# Yard Arena Web

Dependency-free local ship builder, Pareto leaderboard, and mission evidence
viewer for `mercury-1778-outbound-v0`.

Open `index.html` directly. It does not require a server or external runtime.
The builder performs the same declarative preflight gates as the Arena v0
mission and exports `yard.arena.submission.v0` JSON. It is not the authoritative
simulator; the executable `yard-mercury` backend produces the checked-in
`simulation-result.reference.json` and replay, and the pinned Arena evaluator
turns that artifact into a six-objective scorecard.

The checked-in leaderboard entries are visibly marked `DEMO`. Imported
scorecards are checked against the complete v0 wire shape, Mercury identity,
six-objective contract, and replay/environment/season digest fields. Import
does not retrieve or verify the bound artifacts or detached Ed25519 envelope,
so imported results remain unofficial.

The evidence view records the current boundary: the CLIWOC route ensemble is a
reproducible 76,184-observation empirical dataset, while exact daily *Mercury*
log transcription, a reconstructed trajectory, and calibrated historical
prices remain unimplemented.

## Browser smoke test

The test accepts a Playwright module URL rather than adding a web dependency to
Yard:

```sh
PLAYWRIGHT_MODULE=file:///path/to/node_modules/playwright/index.mjs \
ARENA_SCORECARD=/tmp/yard-arena-score.json \
node tests/smoke.mjs
```

It exercises direct-file rendering, live feasibility changes, tabs, track
filters, six-objective scorecard import, provenance rendering, SVG points,
desktop/mobile overflow, the bitmap asset, and browser console errors.
