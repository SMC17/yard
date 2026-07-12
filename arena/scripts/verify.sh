#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MISSION="$ROOT/missions/mercury-1778-outbound-v0/mission.json"
SUBMISSION="$ROOT/missions/mercury-1778-outbound-v0/submission.example.json"
RESULT="$ROOT/missions/mercury-1778-outbound-v0/simulation-result.reference.json"
REPLAY="$ROOT/missions/mercury-1778-outbound-v0/replay.reference.jsonl"
ENVIRONMENT="$ROOT/missions/mercury-1778-outbound-v0/environment/cliwoc-route-ensemble.v0.json"
BACKEND_CONFIG="$ROOT/missions/mercury-1778-outbound-v0/backend-config.json"
YARD=$(CDPATH= cd -- "$ROOT/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

cd "$ROOT"
zig fmt --check build.zig src
find schema missions -name '*.json' -print0 | xargs -0 -n1 jq empty
zig build test --summary all
zig build install
python3 tools/test_ingest_cliwoc.py
python3 tools/test_validate_log_ledger.py
python3 tools/validate_log_ledger.py \
    missions/mercury-1778-outbound-v0/log/route-anchors.v0.json \
    > "$TMP/log-ledger-status.json"
jq -e '.valid == true and .records == 5 and .transcription_records == 0' "$TMP/log-ledger-status.json" >/dev/null
zig build rng-vector -- 42 0 7 > "$TMP/rng-vector.json"
jq -e '.algorithm == "blake3-counter-v1" and .u64_hex == "99bc0b490101ad93"' "$TMP/rng-vector.json" >/dev/null

mission_hash=$(sha256sum "$MISSION" | cut -d' ' -f1)
submission_hash=$(sha256sum "$SUBMISSION" | cut -d' ' -f1)
test "$mission_hash" = "$(jq -r .mission_sha256 "$RESULT")"
test "$submission_hash" = "$(jq -r .submission_sha256 "$RESULT")"

(cd "$YARD/sailmission" && zig build)
MERCURY="$YARD/sailmission/zig-out/bin/yard-mercury"
"$MERCURY" eval "$MISSION" "$SUBMISSION" "$ENVIRONMENT" "$BACKEND_CONFIG" \
    --seed 17781001 --output "$TMP/result-a.json" --replay "$TMP/replay-a.jsonl"
"$MERCURY" eval "$MISSION" "$SUBMISSION" "$ENVIRONMENT" "$BACKEND_CONFIG" \
    --seed 17781001 --output "$TMP/result-b.json" --replay "$TMP/replay-b.jsonl"
cmp "$TMP/result-a.json" "$TMP/result-b.json"
cmp "$TMP/replay-a.jsonl" "$TMP/replay-b.jsonl"
cmp "$TMP/result-a.json" "$RESULT"
cmp "$TMP/replay-a.jsonl" "$REPLAY"
replay_head=$(jq -r .replay_head_sha256 "$RESULT")
zig-out/bin/yard-arena-replay verify "$REPLAY" --head "$replay_head" > "$TMP/replay-status.json"
jq -e '.valid == true and .events == 770' "$TMP/replay-status.json" >/dev/null
jq -e '.selection.selected_observations == 76184 and .source.archive_sha256 == "b574909d59cc5d3f9bbf9b65eadf1358d5eae23d7f63dc8f8f0a740be8476be7"' "$ENVIRONMENT" >/dev/null

zig-out/bin/yard-arena-score "$MISSION" "$SUBMISSION" "$RESULT" > "$TMP/score-a.json"
zig-out/bin/yard-arena-score "$MISSION" "$SUBMISSION" "$RESULT" > "$TMP/score-b.json"
cmp "$TMP/score-a.json" "$TMP/score-b.json"
jq -e '.feasible == true and (.objectives | length) == 6 and .backend_version == "yard-mercury-empirical-sail-v0.1.0"' "$TMP/score-a.json" >/dev/null

cp "$SUBMISSION" "$TMP/tampered-submission.json"
sed -i 's/"unit_cost_units": 300.0/"unit_cost_units": 301.0/' "$TMP/tampered-submission.json"
if zig-out/bin/yard-arena-score "$MISSION" "$TMP/tampered-submission.json" "$RESULT" > "$TMP/tamper.out" 2> "$TMP/tamper.err"; then
    printf '%s\n' "tampered submission unexpectedly scored" >&2
    exit 1
fi
grep -q 'DigestMismatch' "$TMP/tamper.err"

cp "$REPLAY" "$TMP/tampered-replay.jsonl"
sed -i '0,/days=/{s/days=/days=9/}' "$TMP/tampered-replay.jsonl"
if zig-out/bin/yard-arena-replay verify "$TMP/tampered-replay.jsonl" >/dev/null 2>&1; then
    printf '%s\n' "tampered replay unexpectedly verified" >&2
    exit 1
fi

printf '%064d\n' 0 > "$TMP/season-seed.hex"
printf '%s\n' '{"schema":"yard.arena.hidden-season.v0","seeds":[17789991,17789992]}' > "$TMP/hidden-season.json"
zig-out/bin/yard-arena-season sign "$TMP/hidden-season.json" "$TMP/season-seed.hex" test-organizer "$TMP/hidden-season.sig.json" >/dev/null
season_public_key=$(jq -r .public_key_hex "$TMP/hidden-season.sig.json")
zig-out/bin/yard-arena-season verify "$TMP/hidden-season.json" "$TMP/hidden-season.sig.json" test-organizer "$season_public_key" > "$TMP/season-status.json"
jq -e '.valid == true and .algorithm == "ed25519-domain-sha256-v2"' "$TMP/season-status.json" >/dev/null

printf '%s\n' "yard-arena verify: ok tests=18 backend=mercury replay_events=770 corpus_observations=76184 qdl_catalogue_anchors=5 deterministic=true tamper_rejected=true signed_season=true"
