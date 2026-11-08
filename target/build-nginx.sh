#!/usr/bin/env bash
# Phase 7 — build two nginx binaries that differ ONLY in the OpenSSL underneath.
#
#   Arm A ("ossl30"): nginx linked against the distro OpenSSL (Ubuntu 24.04 → 3.0.13)
#   Arm B ("ossl35"): same nginx source, same configure flags, OpenSSL 3.5.2 compiled
#                     in statically via --with-openssl (the common way to run a newer
#                     OpenSSL than the distro ships)
#
# Both share one --prefix (/opt/nginx) so they read the same config/pid paths. That is
# what makes the live binary swap (USR2) possible later: the running master re-execs
# /opt/nginx/sbin/nginx, so "swapping" = copying the other arm's binary over that path.
#
# Writes: $OUT/build.csv  (arm, configure_s, make_s, total_s, binary_bytes, stripped_bytes, openssl)
#         /opt/nginx/sbin/nginx.ossl30, /opt/nginx/sbin/nginx.ossl35
# Usage:  sudo -E ./build-nginx.sh
set -euo pipefail

NGINX_VERSION=${NGINX_VERSION:-1.28.0}
OPENSSL_VERSION=${OPENSSL_VERSION:-3.5.2}
PREFIX=/opt/nginx
WORK=${WORK:-/opt/build}
OUT=${OUT:-/opt/phase7/results}
JOBS=${JOBS:-$(nproc)}

mkdir -p "$WORK" "$OUT"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential libpcre2-dev zlib1g-dev libssl-dev curl ca-certificates >/dev/null

cd "$WORK"
[ -f nginx-$NGINX_VERSION.tar.gz ] || curl -fsSLO \
  "https://github.com/nginx/nginx/releases/download/release-$NGINX_VERSION/nginx-$NGINX_VERSION.tar.gz"
[ -f openssl-$OPENSSL_VERSION.tar.gz ] || curl -fsSLO \
  "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"

COMMON_FLAGS=(
  --prefix=$PREFIX
  --with-http_ssl_module
  --with-http_v2_module
  --with-http_stub_status_module
  --with-threads
)

echo "arm,configure_s,make_s,total_s,binary_bytes,stripped_bytes,openssl" > "$OUT/build.csv"

build_arm() {
  local arm=$1; shift
  local src="$WORK/$arm/nginx-$NGINX_VERSION"
  rm -rf "$WORK/$arm"; mkdir -p "$WORK/$arm"
  tar -xzf "$WORK/nginx-$NGINX_VERSION.tar.gz" -C "$WORK/$arm"
  if [ "$arm" = ossl35 ]; then
    tar -xzf "$WORK/openssl-$OPENSSL_VERSION.tar.gz" -C "$WORK/$arm"
  fi
  cd "$src"

  echo "==> [$arm] configure"
  local t0=$(date +%s.%N)
  ./configure "${COMMON_FLAGS[@]}" "$@" > "$OUT/configure-$arm.log" 2>&1
  local t1=$(date +%s.%N)
  echo "==> [$arm] make -j$JOBS (OpenSSL compile included for ossl35)"
  make -j"$JOBS" > "$OUT/make-$arm.log" 2>&1
  local t2=$(date +%s.%N)

  [ -x "$PREFIX/sbin/nginx" ] || make install > /dev/null   # first arm lays out prefix
  install -m 0755 objs/nginx "$PREFIX/sbin/nginx.$arm"
  local size=$(stat -c %s objs/nginx)
  local stripped=$(strip -o /tmp/nginx-stripped-$arm objs/nginx && stat -c %s /tmp/nginx-stripped-$arm)
  local ossl=$("$PREFIX/sbin/nginx.$arm" -V 2>&1 | sed -n 's/.*\(built with\|running with\) OpenSSL \([^ ]*\).*/\2/p' | head -1)
  python3 - "$arm" "$t0" "$t1" "$t2" "$size" "$stripped" "$ossl" >> "$OUT/build.csv" <<'PY'
import sys
arm, t0, t1, t2, size, stripped, ossl = sys.argv[1:]
t0, t1, t2 = map(float, (t0, t1, t2))
print(f"{arm},{t1-t0:.1f},{t2-t1:.1f},{t2-t0:.1f},{size},{stripped},{ossl}")
PY
}

build_arm ossl30
build_arm ossl35 --with-openssl="$WORK/ossl35/openssl-$OPENSSL_VERSION" \
                 --with-openssl-opt="no-tests no-docs"

# Arm A is the starting state.
install -m 0755 "$PREFIX/sbin/nginx.ossl30" "$PREFIX/sbin/nginx"

echo
python3 -c "import csv,sys; r=list(csv.reader(open(sys.argv[1]))); w=[max(len(x[i]) for x in r) for i in range(len(r[0]))]; [print('  '.join(c.ljust(w[i]) for i,c in enumerate(x))) for x in r]" "$OUT/build.csv"
echo
for a in ossl30 ossl35; do
  echo "== $a"; "$PREFIX/sbin/nginx.$a" -V 2>&1 | grep -E "built with|running with|nginx version"
  echo "   shared libs: $(ldd "$PREFIX/sbin/nginx.$a" | wc -l)  libssl: $(ldd "$PREFIX/sbin/nginx.$a" | grep -c libssl || true)"
done
