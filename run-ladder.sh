#!/usr/bin/env bash
# CPU ladder v2 — what does a handshake cost the server, and where is the ceiling?
#
# 3 arms × RATES × TRIALS, each 60 s of fresh full handshakes, run in a shuffled (but
# reproducible) order so slow drift on the host can't line up with one arm. CPU is taken
# from nginx's own processes (sampler.py), not the whole host.
#
#   ossl30/classical vs ossl35/classical  → cost of the OpenSSL upgrade alone
#   ossl35/classical vs ossl35/pq         → cost of the ML-KEM hybrid alone
#
# Resumable: finished runs (meta.json present) are skipped.
# Usage: ./run-ladder.sh      (TARGET / LOADGEN / TARGET_ADDR / SSH_KEY exported)
set -euo pipefail
cd "$(dirname "$0")"
RATES=${RATES:-"1000 2000 3000 4000"}
TRIALS=${TRIALS:-3}
DUR=${DUR:-60}
SEED=${SEED:-7}
RESULTS=${RESULTS:-results}
export RESULTS

# Fresh instances need nginx built first; keep the original build timings untouched.
if ! RESULTS="$RESULTS/rebuild" ./run.sh footprint >/dev/null 2>&1; then
  echo "==> nginx not built on this target yet — building (~3 min)"
  RESULTS="$RESULTS/rebuild" ./run.sh build
fi

plan=$(python3 - "$RATES" "$TRIALS" "$SEED" <<'PY'
import random, sys
rates, trials, seed = sys.argv[1].split(), int(sys.argv[2]), int(sys.argv[3])
arms = [("ossl30", "classical"), ("ossl35", "classical"), ("ossl35", "pq")]
runs = [(a, p, r, f"L{t}") for t in range(1, trials + 1) for r in rates for a, p in arms]
random.Random(seed).shuffle(runs)
for r in runs:
    print(*r)
PY
)
total=$(wc -l <<< "$plan"); n=0
while read -r -u 3 arm profile rate trial; do
  n=$((n + 1))
  id="soak-$arm-$profile-r$rate-t$trial"
  if [ -f "$RESULTS/$id/meta.json" ]; then echo "skip $id (done)"; continue; fi
  echo "---- [$n/$total]"
  DUR=$DUR ./run.sh soak "$arm" "$profile" "$rate" "$trial"
done 3<<< "$plan"

python3 analyze.py "$RESULTS"
