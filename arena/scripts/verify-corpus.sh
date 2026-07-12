#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REFERENCE="$ROOT/missions/mercury-1778-outbound-v0/environment/cliwoc-route-ensemble.v0.json"
URL="https://hs.pangaea.de/Projects/CLIWOC/CLIWOC21CORE.zip"
EXPECTED="b574909d59cc5d3f9bbf9b65eadf1358d5eae23d7f63dc8f8f0a740be8476be7"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

curl -L --fail --retry 3 -A 'yard-research/0.1' \
    -o "$TMP/CLIWOC21CORE.zip" "$URL"
actual=$(sha256sum "$TMP/CLIWOC21CORE.zip" | cut -d' ' -f1)
test "$actual" = "$EXPECTED"

python3 "$ROOT/tools/ingest_cliwoc.py" \
    --core-zip "$TMP/CLIWOC21CORE.zip" \
    --output "$TMP/cliwoc-route-ensemble.v0.json" \
    > "$TMP/ingest-status.json"
cmp "$TMP/cliwoc-route-ensemble.v0.json" "$REFERENCE"
jq -e '.selected_observations == 76184 and .source_sha256 == "b574909d59cc5d3f9bbf9b65eadf1358d5eae23d7f63dc8f8f0a740be8476be7"' \
    "$TMP/ingest-status.json" >/dev/null

printf '%s\n' "yard-arena corpus verify: ok source_sha256=$EXPECTED observations=76184 byte_identical=true"
