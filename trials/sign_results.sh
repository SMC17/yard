#!/usr/bin/env bash
# Sign every leaderboard + campaign results file with the trials evaluator
# key. Verification is public (allowed_signers is committed); signing needs
# the private key (operator-local or CI secret).
#   sign:   trials/sign_results.sh [keyfile]
#   verify: trials/sign_results.sh --verify
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--verify" ]; then
  fail=0
  for f in trials/results/*.jsonl trials/results/*.json; do
    [ -f "$f" ] || continue
    [ -f "$f.sig" ] || { echo "UNSIGNED: $f"; fail=1; continue; }
    if ssh-keygen -Y verify -f trials/allowed_signers -I trials-evaluator \
        -n yard-trials -s "$f.sig" < "$f" > /dev/null 2>&1; then
      echo "ok: $f"
    else
      echo "BAD SIGNATURE: $f"; fail=1
    fi
  done
  exit $fail
fi
KEY="${1:-$HOME/.local/state/stax/yard-trials-signing}"
for f in trials/results/*.jsonl trials/results/*.json; do
  [ -f "$f" ] && ssh-keygen -Y sign -f "$KEY" -n yard-trials "$f" 2>/dev/null && echo "signed: $f"
done
