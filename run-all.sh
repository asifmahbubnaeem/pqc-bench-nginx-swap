#!/usr/bin/env bash
# Full Phase 7 matrix, in order. ~80 min of runs after the ~10 min build.
# Resumable: a run whose results dir already has meta.json is skipped.
# Usage: ./run-all.sh            (TARGET / LOADGEN / TARGET_ADDR / SSH_KEY exported)
set -euo pipefail
cd "$(dirname "$0")"
RATE=${RATE:-500}
TRIALS=${TRIALS:-3}
RESULTS=${RESULTS:-results}

run() {  # run SCENARIO ARM PROFILE RATE TRIAL
  local id="$1-$2-$3-r$4-t$5"
  [ "$1" = idle ] && id="$1-$2-$3-r0-t$5"
  if [ -f "$RESULTS/$id/meta.json" ]; then echo "skip $id (done)"; return; fi
  ./run.sh "$@"
}

[ -f "$RESULTS/build/build.csv" ] || ./run.sh build
[ -f "$RESULTS/footprint/footprint.csv" ] || ./run.sh footprint

# 1. idle memory, each arm in its natural profile
run idle ossl30 classical 0 1
run idle ossl35 pq        0 1

# 2. config reload under load — 9 reloads, 30 s apart
for t in $(seq "$TRIALS"); do
  run reload ossl30 classical "$RATE" "$t"
  run reload ossl35 pq        "$RATE" "$t"
done

# 3. live binary swap A→B, naive rollback, correct rollback
for t in $(seq "$TRIALS"); do run swap ossl30 classical "$RATE" "$t"; done

# 4. swap + fast rollback while the old master is still alive
for t in $(seq "$TRIALS"); do run swap-fast-rollback ossl30 classical "$RATE" "$t"; done

# 5. memory soak — 10 min of fresh full handshakes per arm
DUR=${SOAK_DUR:-600} run soak ossl30 classical "$RATE" 1
DUR=${SOAK_DUR:-600} run soak ossl35 pq        "$RATE" 1

# 6. CPU ladder — 60 s per step. Three arms so the two variables separate:
#    ossl30/classical vs ossl35/classical = cost of the OpenSSL upgrade alone
#    ossl35/classical vs ossl35/pq        = cost of the ML-KEM hybrid alone
for r in ${LADDER_RATES:-500 1000 2000}; do
  DUR=${LADDER_DUR:-60} run soak ossl30 classical "$r" ladder
  DUR=${LADDER_DUR:-60} run soak ossl35 classical "$r" ladder
  DUR=${LADDER_DUR:-60} run soak ossl35 pq        "$r" ladder
done

python3 analyze.py "$RESULTS"
