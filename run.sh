#!/usr/bin/env bash
# Phase 7 orchestrator — run from your laptop (or with TARGET=local LOADGEN=local on one box).
#
# Setup:
#   export TARGET=ubuntu@<target-public-ip>      # ssh login for the nginx box
#   export LOADGEN=ubuntu@<loadgen-public-ip>    # ssh login for the load generator
#   export TARGET_ADDR=<target-PRIVATE-ip>       # what the loadgen connects to (same VPC)
#   export SSH_KEY=~/.ssh/pqc-bench.pem
#
#   ./run.sh deploy                 copy scripts + loadgen binary to the hosts
#   ./run.sh build                  build both nginx arms on the target (timed)
#   ./run.sh footprint              static footprint (binary + shared TLS libs)
#   ./run.sh SCENARIO ARM PROFILE [RATE] [TRIAL]
#       SCENARIO: idle | soak | reload | swap | swap-fast-rollback
#       ARM: ossl30 | ossl35        PROFILE: classical | pq
#
# Results land in ./results/<scenario>-<arm>-<profile>-r<rate>-t<trial>/
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${TARGET:?set TARGET}" "${LOADGEN:?set LOADGEN}"
TARGET_ADDR=${TARGET_ADDR:-127.0.0.1}
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -o ConnectTimeout=20 -o ConnectionAttempts=5)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")
REMOTE=/opt/phase7
RESULTS=${RESULTS:-$HERE/results}

on() {  # on HOST "script" — run as root on HOST (or locally)
  local host=$1 script=$2
  if [ "$host" = local ]; then
    if [ "$(id -u)" = 0 ]; then bash -s <<< "$script"; else sudo bash -s <<< "$script"; fi
  else
    ssh "${SSH_OPTS[@]}" "$host" "sudo bash -s" <<< "$script"
  fi
}
fetch() {  # fetch HOST REMOTE_DIR LOCAL_DIR
  if [ "$1" = local ]; then cp -r "$2"/. "$3"/
  else
    on "$1" "chmod -R a+r $2" >/dev/null
    scp "${SSH_OPTS[@]}" -q -r "$1:$2/." "$3/"
  fi
}
push() {  # push HOST LOCAL_PATH... REMOTE_DIR
  local host=$1; shift; local dest=${!#}; local srcs=("${@:1:$#-1}")
  on "$host" "mkdir -p $dest && chmod 777 $dest"
  if [ "$host" = local ]; then cp -r "${srcs[@]}" "$dest"/
  else scp "${SSH_OPTS[@]}" -q -r "${srcs[@]}" "$host:$dest/"; fi
}

case "${1:-}" in
deploy)
  push "$TARGET" "$HERE/target" "$REMOTE"
  on "$TARGET" "chmod +x $REMOTE/target/*.sh $REMOTE/target/*.py"
  LG_BIN=${LOADGEN_BIN:-$HERE/loadgen/pq-loadgen-linux-arm64}
  push "$LOADGEN" "$LG_BIN" "$REMOTE"
  on "$LOADGEN" "[ $(basename "$LG_BIN") = pq-loadgen ] || mv -f $REMOTE/$(basename "$LG_BIN") $REMOTE/pq-loadgen; chmod +x $REMOTE/pq-loadgen; ulimit -n"
  echo "deployed."
  exit 0 ;;
build)
  on "$TARGET" "OUT=$REMOTE/results $REMOTE/target/build-nginx.sh"
  mkdir -p "$RESULTS/build"; fetch "$TARGET" "$REMOTE/results" "$RESULTS/build"
  exit 0 ;;
footprint)
  on "$TARGET" "$REMOTE/target/footprint.sh $REMOTE/results/footprint"
  mkdir -p "$RESULTS/footprint"; fetch "$TARGET" "$REMOTE/results/footprint" "$RESULTS/footprint"
  exit 0 ;;
esac

SCEN=${1:?usage: run.sh SCENARIO ARM PROFILE [RATE] [TRIAL]}
ARM=${2:?}; PROFILE=${3:?}; RATE=${4:-500}; TRIAL=${5:-1}
WARM=${WARM:-30}
case "$SCEN" in
  idle)               DUR=${DUR:-60};  RATE=0 ;;
  soak)               DUR=${DUR:-600} ;;
  reload)             DUR=${DUR:-$((WARM + ${RELOADS:-9} * ${RELOAD_EVERY:-30} + 15))} ;;
  swap)               DUR=${DUR:-$((WARM + 2 * ${GAP:-45} + 60))} ;;
  swap-fast-rollback) DUR=${DUR:-$((WARM + ${GAP:-30} + 45))} ;;
  *) echo "unknown scenario $SCEN"; exit 1 ;;
esac
ID="$SCEN-$ARM-$PROFILE-r$RATE-t$TRIAL"
RDIR=$REMOTE/runs/$ID
OUTDIR=$RESULTS/$ID
mkdir -p "$OUTDIR"
echo "==> $ID  (duration ${DUR}s, rate ${RATE}/s)"

on "$TARGET" "rm -rf $RDIR; mkdir -p $RDIR; $REMOTE/target/scenario.sh start $RDIR $ARM $PROFILE"
on "$TARGET" "nohup $REMOTE/target/sampler.sh $RDIR/sampler.csv >/dev/null 2>&1 & echo \$! > $RDIR/sampler.pid"

LG_PID=""
if [ "$RATE" -gt 0 ]; then
  on "$LOADGEN" "mkdir -p $REMOTE/runs/$ID; ulimit -n 65536; cd $REMOTE && ./pq-loadgen -url https://$TARGET_ADDR/ -rate $RATE -duration ${DUR}s -groups default -out runs/$ID/loadgen.csv; gzip -f runs/$ID/loadgen.csv" \
    > "$OUTDIR/loadgen.stderr" 2>&1 &
  LG_PID=$!
  sleep 1
fi

on "$TARGET" "WARM=$WARM RELOADS=${RELOADS:-9} RELOAD_EVERY=${RELOAD_EVERY:-30} GAP=${GAP:-} $REMOTE/target/scenario.sh events $RDIR $SCEN" \
  2> >(sed 's/^/    [target] /' >&2)

if [ -n "$LG_PID" ]; then wait "$LG_PID" || true; else sleep "$DUR"; fi
on "$TARGET" "kill \$(cat $RDIR/sampler.pid) 2>/dev/null; $REMOTE/target/scenario.sh stop $RDIR; gzip -f $RDIR/bench.log 2>/dev/null || true"

fetch "$TARGET" "$RDIR" "$OUTDIR"
[ -n "$LG_PID" ] && fetch "$LOADGEN" "$REMOTE/runs/$ID" "$OUTDIR"
cat > "$OUTDIR/meta.json" <<EOF
{"scenario": "$SCEN", "arm": "$ARM", "profile": "$PROFILE", "rate": $RATE, "trial": "$TRIAL",
 "duration_s": $DUR, "warm_s": $WARM, "finished_utc": "$(date -u +%FT%TZ)"}
EOF
tail -3 "$OUTDIR/loadgen.stderr" 2>/dev/null || true
echo "==> results: $OUTDIR"
