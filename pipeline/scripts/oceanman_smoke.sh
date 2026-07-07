#!/usr/bin/env bash
# oceanman_smoke.sh: runs the cable_route_consumer against a fixed
# oceanman cable id and emits the LayPlan to stdout. Default cable is
# `aden-djibouti` (269 km Red Sea route, 2 landings); pass
# OCEANMAN_CABLE_ID to override.
#
# Verdict hypothesis (exp-1780164252-902382970):
#   parses real cable record + emits non-empty LayPlan in under 100ms
#   median over 30 runs.
#
# Substrate-shared-not-identical: see the disclosure block in the
# LayPlan output and the module comment in
# src/cable_route_consumer.zig. A cable record is NOT a pipeline lay
# plan; this wire surfaces shared route-geometry only.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OCEANMAN_ROOT="${OCEANMAN_ROOT:-${HOME}/oceanman}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-${OCEANMAN_ROOT}/data/snapshots/2026-05-07}"
OCEANMAN_CABLE_ID="${OCEANMAN_CABLE_ID:-aden-djibouti}"

CABLE_JSON="${SNAPSHOT_DIR}/cables/${OCEANMAN_CABLE_ID}.json"
LANDING_GEO="${SNAPSHOT_DIR}/landing-point-geo.json"

if [[ ! -f "$CABLE_JSON" ]]; then
  echo "smoke: cable file missing: $CABLE_JSON" >&2
  exit 1
fi
if [[ ! -f "$LANDING_GEO" ]]; then
  echo "smoke: landing-point-geo missing: $LANDING_GEO" >&2
  exit 1
fi

cd "$REPO_ROOT"

# Build once if the artefact is missing or stale.
zig build >/dev/null 2>&1

BIN="${REPO_ROOT}/zig-out/bin/oceanman-smoke"
if [[ ! -x "$BIN" ]]; then
  echo "smoke: binary not built: $BIN" >&2
  exit 1
fi

# Single-shot LayPlan emission to stdout.
"$BIN" "$CABLE_JSON" "$LANDING_GEO"

# Verdict gate: 30-run median parse time. Emit to stderr so stdout
# stays clean for the LayPlan consumer downstream.
if [[ "${SMOKE_TIMING_GATE:-1}" == "1" ]]; then
  echo >&2
  echo "# Timing gate (30 runs, median):" >&2
  TIMES_FILE="$(mktemp)"
  trap 'rm -f "$TIMES_FILE"' EXIT
  for _ in $(seq 1 30); do
    "$BIN" "$CABLE_JSON" "$LANDING_GEO" >/dev/null 2>"$TIMES_FILE.one"
    awk -F'=' '/^parse_us=/ {sub(/ .*/, "", $2); print $2}' "$TIMES_FILE.one" >> "$TIMES_FILE"
  done
  MEDIAN_US=$(sort -n "$TIMES_FILE" | awk 'NR == 15 {print; exit}')
  MEDIAN_MS=$(awk -v us="$MEDIAN_US" 'BEGIN {printf "%.3f", us / 1000.0}')
  echo "median_parse_us=$MEDIAN_US median_parse_ms=$MEDIAN_MS gate=100ms" >&2
  AWK_PASS=$(awk -v ms="$MEDIAN_MS" 'BEGIN {print (ms < 100.0) ? 1 : 0}')
  if [[ "$AWK_PASS" == "1" ]]; then
    echo "verdict=pass" >&2
  else
    echo "verdict=fail" >&2
    exit 1
  fi
fi
