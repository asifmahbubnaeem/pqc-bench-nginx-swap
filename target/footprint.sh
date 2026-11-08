#!/usr/bin/env bash
# Static footprint of both arms: binary size, and the TLS code each one actually loads.
# Arm A's binary is small because libssl/libcrypto live in shared libraries; arm B carries
# OpenSSL inside the binary. Counting the shared libs makes the comparison fair.
# Usage: footprint.sh OUT_DIR
set -euo pipefail
OUT=${1:?}
mkdir -p "$OUT"
P=/opt/nginx/sbin
echo "arm,binary_bytes,stripped_bytes,shared_ssl_libs_bytes,tls_total_bytes,shared_lib_count,openssl" > "$OUT/footprint.csv"
for arm in ossl30 ossl35; do
  b=$P/nginx.$arm
  size=$(stat -c %s "$b")
  stripped=$(strip -o /tmp/fp-$arm "$b" && stat -c %s /tmp/fp-$arm)
  libs=0
  for so in $(ldd "$b" | awk '/libssl|libcrypto/ {print $3}'); do
    libs=$((libs + $(stat -L -c %s "$so")))
  done
  nlibs=$(ldd "$b" | grep -c '=>' || true)
  ossl=$("$b" -V 2>&1 | sed -n 's/^built with OpenSSL \([^ ]*\).*/\1/p')
  echo "$arm,$size,$stripped,$libs,$((stripped + libs)),$nlibs,$ossl" >> "$OUT/footprint.csv"
  ldd "$b" > "$OUT/ldd-$arm.txt"
  "$b" -V > "$OUT/nginx-V-$arm.txt" 2>&1
done
cat "$OUT/footprint.csv"
