#!/usr/bin/env bash
# Phase 7 target-side actions. Every action that touches nginx writes a timestamped line
# to $RUN/events.log so the analysis can line up client errors with server events.
#
#   scenario.sh start  RUN ARM PROFILE     stop nginx, install binary+config, clear logs, start
#   scenario.sh events RUN NAME            run the event schedule for scenario NAME (blocking)
#   scenario.sh stop   RUN                 graceful stop, copy logs into RUN
#
# ARM: ossl30 | ossl35    PROFILE: classical | pq
# NAME: idle | soak | reload | swap | swap-fast-rollback   (see schedules below)
set -euo pipefail
P=/opt/nginx
BIN=$P/sbin/nginx
HERE=$(cd "$(dirname "$0")" && pwd)

cmd=${1:?}; RUN=${2:?}
mkdir -p "$RUN"
ev() { echo "$(date +%s.%N) $*" | tee -a "$RUN/events.log" >&2; }
master_pid() { cat "$P/logs/nginx.pid" 2>/dev/null || true; }

# Replace the binary atomically: copy beside it, then rename over it. A plain `cp` onto a
# running executable fails with "Text file busy"; rename swaps the directory entry while
# the running master keeps its old inode.
put_binary() {
  cp "$BIN.$1" "$BIN.next"
  mv -f "$BIN.next" "$BIN"
}

# After USR2 nginx renames the pid file to .oldbin *before* the new binary has parsed its
# config; if the new master then fails, it exits and the rename is undone. So only count a
# swap as successful when, a moment later, .oldbin still exists and two masters are running.
new_master_ok() {
  sleep 1.5
  [ -f "$P/logs/nginx.pid.oldbin" ] && [ "$(pgrep -fc 'nginx: master process')" -ge 2 ]
}

wait_for() {  # wait_for SECONDS CMD... — poll until CMD succeeds
  local t=$1; shift
  for _ in $(seq $((t * 10))); do "$@" && return 0; sleep 0.1; done
  return 1
}

# Live binary upgrade (nginx docs, "Upgrading Executable on the Fly"):
#   USR2 → old master execs the new binary (new master + workers, both generations serve)
#   WINCH → old workers finish in-flight requests and exit
#   QUIT  → old master exits
upgrade() {   # upgrade ARM PROFILE [keep_old_seconds]
  local arm=$1 profile=$2 keep=${3:-10}
  local old; old=$(master_pid)
  ev "swap_begin to=$arm profile=$profile old_master=$old"
  "$HERE/make-conf.sh" "$profile" >/dev/null
  put_binary "$arm"
  if ! "$BIN" -t >/dev/null 2>"$RUN/nginx-t.err"; then
    ev "swap_config_test_failed $(tr '\n' ' ' < "$RUN/nginx-t.err" | cut -c1-200)"
  fi
  kill -USR2 "$old"
  ev "usr2 old_master=$old"
  if ! new_master_ok; then
    ev "swap_failed new_master_did_not_start (old master $old still serving)"
    return 1
  fi
  ev "new_master_up new_master=$(master_pid)"
  sleep 5
  kill -WINCH "$old"; ev "winch old_master=$old"
  sleep "$keep"
  kill -QUIT "$old"; ev "quit old_master=$old"
  wait_for 10 bash -c "! kill -0 $old 2>/dev/null" || ev "old_master_still_alive $old"
  ev "swap_done master=$(master_pid)"
}

case "$cmd" in
start)
  ARM=${3:?}; PROFILE=${4:?}
  if [ -s "$P/logs/nginx.pid" ] && kill -0 "$(master_pid)" 2>/dev/null; then
    "$BIN" -s quit || true
    wait_for 15 bash -c "! pgrep -x nginx >/dev/null" || pkill -9 -x nginx || true
  fi
  rm -f "$P/logs/"*.log "$P/logs/nginx.pid"*
  "$HERE/make-conf.sh" "$PROFILE" >/dev/null
  put_binary "$ARM"
  "$BIN" -t
  ulimit -n 65536 2>/dev/null || true
  "$BIN"
  ev "start arm=$ARM profile=$PROFILE master=$(master_pid) openssl=$("$BIN" -V 2>&1 | sed -n 's/^built with OpenSSL \([^ ]*\).*/\1/p')"
  ;;

events)
  NAME=${3:?}
  WARM=${WARM:-30}
  case "$NAME" in
  idle|soak)
    ;;  # no events: the load (or lack of it) is the experiment
  reload)
    # every RELOAD_EVERY s after warm-up: config reload under load
    EVERY=${RELOAD_EVERY:-30}; N=${RELOADS:-9}
    sleep "$WARM"
    for i in $(seq "$N"); do
      ev "reload n=$i master=$(master_pid)"
      "$BIN" -s reload
      sleep "$EVERY"
    done
    ;;
  swap)
    # forward swap A→B; naive rollback (binary only, PQ config left in place);
    # then the correct rollback (config first, then binary).
    sleep "$WARM"
    upgrade ossl35 pq
    sleep "${GAP:-45}"
    ev "naive_rollback_begin (binary→ossl30, config left as pq)"
    old=$(master_pid)
    put_binary ossl30
    "$BIN" -t >/dev/null 2>"$RUN/nginx-t-naive.err" && ev "naive_t_ok" \
      || ev "naive_t_failed $(tr '\n' ' ' < "$RUN/nginx-t-naive.err" | cut -c1-160)"
    kill -USR2 "$old"; ev "usr2 old_master=$old (naive)"
    if new_master_ok; then
      ev "naive_new_master_started (unexpected)"
    else
      ev "naive_rollback_failed: new master exited, old master $old still serving ($(grep -c emerg $P/logs/error.log) emerg lines in error.log)"
      put_binary ossl35   # leave disk consistent with what is actually running
    fi
    sleep "${GAP:-45}"
    upgrade ossl30 classical
    ;;
  swap-fast-rollback)
    # forward swap, then roll back while the old master is still alive:
    # HUP old master (respawn its workers, no config re-read) + QUIT new master.
    sleep "$WARM"
    old=$(master_pid)
    ev "swap_begin to=ossl35 profile=pq old_master=$old (fast-rollback variant)"
    "$HERE/make-conf.sh" pq >/dev/null
    put_binary ossl35
    kill -USR2 "$old"; ev "usr2 old_master=$old"
    new_master_ok || { ev "swap_failed"; exit 1; }
    new=$(master_pid); ev "new_master_up new_master=$new"
    sleep 5
    kill -WINCH "$old"; ev "winch old_master=$old"
    sleep "${GAP:-30}"
    ev "fast_rollback_begin"
    kill -HUP "$old"; ev "hup old_master=$old (old workers respawn with old binary+config)"
    sleep 3
    kill -QUIT "$new"; ev "quit new_master=$new"
    wait_for 10 bash -c "! kill -0 $new 2>/dev/null" || ev "new_master_still_alive $new"
    "$HERE/make-conf.sh" classical >/dev/null; put_binary ossl30
    ev "fast_rollback_done master=$(master_pid) (on-disk config+binary restored to match)"
    ;;
  *) echo "unknown scenario $NAME"; exit 1 ;;
  esac
  ev "events_done $NAME"
  ;;

stop)
  sleep 2  # let access_log flush (flush=1s)
  "$BIN" -s quit 2>/dev/null || true
  wait_for 15 bash -c "! pgrep -x nginx >/dev/null" || true
  cp "$P/logs/bench.log" "$P/logs/error.log" "$RUN/" 2>/dev/null || true
  cp "$P/conf/nginx.conf" "$RUN/nginx.conf.final" 2>/dev/null || true
  ;;

*) echo "usage: scenario.sh start|events|stop RUN ..."; exit 1 ;;
esac
