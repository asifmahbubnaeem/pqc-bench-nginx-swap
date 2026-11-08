# Phase 7 results

## Static footprint

`build/build.csv`

| arm | configure_s | make_s | total_s | binary_bytes | stripped_bytes | openssl |
|---|---|---|---|---|---|---|
| ossl30 | 4.3 | 15.7 | 20.1 | 5344504 | 1200408 | 3.0.13 |
| ossl35 | 4.2 | 117.7 | 121.9 | 12711424 | 7646488 | 3.5.2 |

`footprint/footprint.csv`

| arm | binary_bytes | stripped_bytes | shared_ssl_libs_bytes | tls_total_bytes | shared_lib_count | openssl |
|---|---|---|---|---|---|---|
| ossl30 | 5344504 | 1200408 | 5400656 | 6601064 | 6 | 3.0.13 |
| ossl35 | 12711424 | 7646488 | 0 | 7646488 | 4 | 3.5.2 |

## Idle memory

| arm | profile | rss_total_mb_med | rss_master_mb_max | rss_worker_mb_max |
|---|---|---|---|---|
| ossl30 | classical | 23.5 | 2.0 | 10.8 |
| ossl35 | pq | 24.1 | 2.3 | 10.9 |

## Runs under load

| scenario | arm | profile | rate | trial | requests | errors | error_pct | error_kinds | req_p50 | req_p99 | req_p999 | tls_p50 | tls_p99 | quiet_p99 | cpu_busy_med_pct | rss_total_mb_med | rss_worker_mb_max | rss_slope_mb_per_h | pq_share_pct | worker_pids_seen |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| reload | ossl30 | classical | 500 | 1 | 157501 | 0 | 0.0 |  | 1.59 | 2.17 | 2.81 | 0.72 | 0.84 | 2.17 | 12.1 | 34.1 | 14.1 |  | 0.0 | 20 |
| reload | ossl30 | classical | 500 | 2 | 157501 | 0 | 0.0 |  | 1.6 | 2.18 | 2.96 | 0.73 | 0.86 | 2.18 | 12.1 | 34.1 | 14.1 |  | 0.0 | 20 |
| reload | ossl30 | classical | 500 | 3 | 157501 | 0 | 0.0 |  | 1.58 | 2.16 | 2.66 | 0.72 | 0.84 | 2.16 | 11.2 | 34.0 | 14.1 |  | 0.0 | 20 |
| reload | ossl35 | pq | 500 | 1 | 157501 | 0 | 0.0 |  | 1.68 | 2.3 | 3.03 | 0.83 | 0.98 | 2.3 | 11.5 | 35.5 | 14.7 |  | 100.0 | 20 |
| reload | ossl35 | pq | 500 | 2 | 157501 | 0 | 0.0 |  | 1.66 | 2.28 | 2.7 | 0.82 | 0.96 | 2.29 | 13.4 | 35.5 | 14.7 |  | 100.0 | 20 |
| reload | ossl35 | pq | 500 | 3 | 157501 | 0 | 0.0 |  | 1.67 | 2.28 | 2.94 | 0.82 | 0.96 | 2.28 | 10.7 | 35.5 | 14.7 |  | 100.0 | 20 |
| soak | ossl30 | classical | 500 | 1 | 300001 | 0 | 0.0 |  | 1.58 | 2.18 | 2.74 | 0.72 | 0.82 | 2.18 | 11.6 | 30.0 | 14.0 | 2.08 | 0.0 | 2 |
| soak | ossl35 | pq | 500 | 1 | 300001 | 0 | 0.0 |  | 1.65 | 2.27 | 2.8 | 0.82 | 0.92 | 2.27 | 10.1 | 31.5 | 14.6 | 2.29 | 100.0 | 2 |
| swap-fast-rollback | ossl30 | classical | 500 | 1 | 52501 | 0 | 0.0 |  | 1.6 | 2.24 | 2.65 | 0.74 | 0.93 | 2.25 | 11.2 | 30.3 | 14.7 |  | 33.3 | 6 |
| swap-fast-rollback | ossl30 | classical | 500 | 2 | 52501 | 0 | 0.0 |  | 1.62 | 2.27 | 2.59 | 0.74 | 0.94 | 2.27 | 13.8 | 30.3 | 14.6 |  | 33.1 | 6 |
| swap-fast-rollback | ossl30 | classical | 500 | 3 | 52501 | 0 | 0.0 |  | 1.6 | 2.25 | 2.74 | 0.74 | 0.93 | 2.26 | 11.7 | 30.4 | 14.6 |  | 33.1 | 6 |
| swap | ossl30 | classical | 500 | 1 | 90001 | 0 | 0.0 |  | 1.64 | 2.26 | 2.71 | 0.81 | 0.92 | 2.27 | 13.7 | 37.1 | 14.6 |  | 60.0 | 6 |
| swap | ossl30 | classical | 500 | 2 | 90001 | 0 | 0.0 |  | 1.65 | 2.29 | 2.75 | 0.81 | 0.95 | 2.29 | 14.1 | 37.1 | 14.7 |  | 60.0 | 6 |
| swap | ossl30 | classical | 500 | 3 | 90001 | 0 | 0.0 |  | 1.64 | 2.28 | 2.63 | 0.81 | 0.95 | 2.29 | 12.1 | 37.1 | 14.6 |  | 60.1 | 6 |

## CPU ladder (nginx processes only, steady window, mean ± sd over trials)

| arm_label | rate | trials | ok_rate | errors | nginx_cores | nginx_cores_sd | us_per_hs | us_per_hs_sd | host_cpu_pct | tls_p50 | req_p99 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A: OpenSSL 3.0, classical | 1000 | 3 | 1000.0 | 0 | 0.412 | 0.006 | 412.333 | 5.774 | 19.5 | 0.713 | 1.98 |
| A: OpenSSL 3.0, classical | 2000 | 3 | 2000.0 | 0 | 0.85 | 0.006 | 424.833 | 3.215 | 48.667 | 0.767 | 1.817 |
| A: OpenSSL 3.0, classical | 3000 | 3 | 3000.0 | 0 | 1.302 | 0.012 | 433.867 | 3.855 | 69.433 | 0.827 | 2.71 |
| A: OpenSSL 3.0, classical | 4000 | 3 | 4000.0 | 0 | 1.73 | 0.008 | 432.4 | 1.905 | 88.633 | 1.213 | 6.203 |
| B: OpenSSL 3.5, classical | 1000 | 3 | 1000.0 | 0 | 0.349 | 0.01 | 349.0 | 10.0 | 26.833 | 0.673 | 2.403 |
| B: OpenSSL 3.5, classical | 2000 | 3 | 2000.0 | 0 | 0.697 | 0.01 | 348.5 | 4.77 | 42.9 | 0.69 | 1.61 |
| B: OpenSSL 3.5, classical | 3000 | 3 | 3000.0 | 0 | 1.064 | 0.006 | 354.567 | 1.963 | 58.967 | 0.72 | 1.89 |
| B: OpenSSL 3.5, classical | 4000 | 3 | 4000.0 | 0 | 1.43 | 0.005 | 357.5 | 1.323 | 75.1 | 0.833 | 94.59 |
| B: OpenSSL 3.5, X25519MLKEM768 | 1000 | 3 | 1000.0 | 0 | 0.402 | 0.006 | 402.333 | 5.774 | 20.567 | 0.81 | 1.81 |
| B: OpenSSL 3.5, X25519MLKEM768 | 2000 | 3 | 2000.0 | 0 | 0.833 | 0.011 | 416.667 | 5.485 | 42.533 | 0.893 | 2.16 |
| B: OpenSSL 3.5, X25519MLKEM768 | 3000 | 3 | 3000.0 | 0 | 1.273 | 0.012 | 424.2 | 3.851 | 68.033 | 0.943 | 2.9 |
| B: OpenSSL 3.5, X25519MLKEM768 | 4000 | 3 | 4000.0 | 0 | 1.688 | 0.018 | 421.9 | 4.564 | 86.867 | 1.307 | 6.017 |

### Cost per full handshake and implied ceiling (2 vCPU, nginx CPU only)

| arm | µs CPU per handshake (median over clean rates) | implied max handshakes/s at 100% CPU |
|---|---|---|
| A: OpenSSL 3.0, classical | 429 | 4,666 |
| B: OpenSSL 3.5, classical | 352 | 5,685 |
| B: OpenSSL 3.5, X25519MLKEM768 | 419 | 4,770 |

OpenSSL 3.0 → 3.5 (classical): -77 µs/handshake (-17.9%).  
Adding X25519MLKEM768 on 3.5: +68 µs/handshake (+19.2%).  
Net, A → B with PQ: -9 µs/handshake (-2.2%).

## Event windows (3 s after each signal)

| run | t_rel_s | event | requests | errors | p99_ms | quiet_p99_ms | max_ms |
|---|---|---|---|---|---|---|---|
| reload-ossl30-classical-r500-t1 | 30.9 | reload n=1 master=26689 | 1500 | 0 | 2.18 | 2.17 | 5.47 |
| reload-ossl30-classical-r500-t1 | 60.9 | reload n=2 master=26689 | 1500 | 0 | 2.2 | 2.17 | 6.37 |
| reload-ossl30-classical-r500-t1 | 90.9 | reload n=3 master=26689 | 1500 | 0 | 2.2 | 2.17 | 3.53 |
| reload-ossl30-classical-r500-t1 | 120.9 | reload n=4 master=26689 | 1500 | 0 | 2.17 | 2.17 | 4.05 |
| reload-ossl30-classical-r500-t1 | 150.9 | reload n=5 master=26689 | 1500 | 0 | 2.22 | 2.17 | 3.2 |
| reload-ossl30-classical-r500-t1 | 180.9 | reload n=6 master=26689 | 1500 | 0 | 2.21 | 2.17 | 10.3 |
| reload-ossl30-classical-r500-t1 | 210.9 | reload n=7 master=26689 | 1500 | 0 | 2.18 | 2.17 | 3.89 |
| reload-ossl30-classical-r500-t1 | 240.9 | reload n=8 master=26689 | 1500 | 0 | 2.19 | 2.17 | 6.42 |
| reload-ossl30-classical-r500-t1 | 270.9 | reload n=9 master=26689 | 1500 | 0 | 2.16 | 2.17 | 3.14 |
| reload-ossl30-classical-r500-t2 | 30.8 | reload n=1 master=30865 | 1500 | 0 | 2.17 | 2.18 | 3.11 |
| reload-ossl30-classical-r500-t2 | 60.8 | reload n=2 master=30865 | 1500 | 0 | 2.2 | 2.18 | 3.35 |
| reload-ossl30-classical-r500-t2 | 90.8 | reload n=3 master=30865 | 1500 | 0 | 2.2 | 2.18 | 4.07 |
| reload-ossl30-classical-r500-t2 | 120.8 | reload n=4 master=30865 | 1500 | 0 | 2.21 | 2.18 | 2.52 |
| reload-ossl30-classical-r500-t2 | 150.8 | reload n=5 master=30865 | 1500 | 0 | 2.2 | 2.18 | 3.41 |
| reload-ossl30-classical-r500-t2 | 180.8 | reload n=6 master=30865 | 1500 | 0 | 2.21 | 2.18 | 3.38 |
| reload-ossl30-classical-r500-t2 | 210.8 | reload n=7 master=30865 | 1500 | 0 | 2.21 | 2.18 | 3.06 |
| reload-ossl30-classical-r500-t2 | 240.9 | reload n=8 master=30865 | 1500 | 0 | 2.2 | 2.18 | 3.12 |
| reload-ossl30-classical-r500-t2 | 270.9 | reload n=9 master=30865 | 1500 | 0 | 2.16 | 2.18 | 4.21 |
| reload-ossl30-classical-r500-t3 | 31.1 | reload n=1 master=37203 | 1500 | 0 | 2.17 | 2.16 | 3.09 |
| reload-ossl30-classical-r500-t3 | 61.1 | reload n=2 master=37203 | 1500 | 0 | 2.17 | 2.16 | 3.06 |
| reload-ossl30-classical-r500-t3 | 91.1 | reload n=3 master=37203 | 1500 | 0 | 2.17 | 2.16 | 3.18 |
| reload-ossl30-classical-r500-t3 | 121.1 | reload n=4 master=37203 | 1500 | 0 | 2.16 | 2.16 | 3.91 |
| reload-ossl30-classical-r500-t3 | 151.1 | reload n=5 master=37203 | 1500 | 0 | 2.16 | 2.16 | 3.01 |
| reload-ossl30-classical-r500-t3 | 181.1 | reload n=6 master=37203 | 1500 | 0 | 2.16 | 2.16 | 3.01 |
| reload-ossl30-classical-r500-t3 | 211.1 | reload n=7 master=37203 | 1500 | 0 | 2.17 | 2.16 | 2.6 |
| reload-ossl30-classical-r500-t3 | 241.2 | reload n=8 master=37203 | 1500 | 0 | 2.18 | 2.16 | 4.85 |
| reload-ossl30-classical-r500-t3 | 271.2 | reload n=9 master=37203 | 1500 | 0 | 2.17 | 2.16 | 4.91 |
| reload-ossl35-pq-r500-t1 | 31.2 | reload n=1 master=28778 | 1500 | 0 | 2.27 | 2.3 | 3.43 |
| reload-ossl35-pq-r500-t1 | 61.2 | reload n=2 master=28778 | 1500 | 0 | 2.33 | 2.3 | 3.23 |
| reload-ossl35-pq-r500-t1 | 91.2 | reload n=3 master=28778 | 1500 | 0 | 2.34 | 2.3 | 3.28 |
| reload-ossl35-pq-r500-t1 | 121.2 | reload n=4 master=28778 | 1500 | 0 | 2.33 | 2.3 | 4.82 |
| reload-ossl35-pq-r500-t1 | 151.2 | reload n=5 master=28778 | 1500 | 0 | 2.33 | 2.3 | 4.19 |
| reload-ossl35-pq-r500-t1 | 181.2 | reload n=6 master=28778 | 1500 | 0 | 2.31 | 2.3 | 3.68 |
| reload-ossl35-pq-r500-t1 | 211.2 | reload n=7 master=28778 | 1500 | 0 | 2.3 | 2.3 | 3.3 |
| reload-ossl35-pq-r500-t1 | 241.2 | reload n=8 master=28778 | 1500 | 0 | 2.31 | 2.3 | 4.32 |
| reload-ossl35-pq-r500-t1 | 271.2 | reload n=9 master=28778 | 1500 | 0 | 2.31 | 2.3 | 4.26 |
| reload-ossl35-pq-r500-t2 | 31.1 | reload n=1 master=35095 | 1500 | 0 | 2.27 | 2.29 | 2.66 |
| reload-ossl35-pq-r500-t2 | 61.1 | reload n=2 master=35095 | 1500 | 0 | 2.27 | 2.29 | 3.9 |
| reload-ossl35-pq-r500-t2 | 91.1 | reload n=3 master=35095 | 1500 | 0 | 2.28 | 2.29 | 3.07 |
| reload-ossl35-pq-r500-t2 | 121.2 | reload n=4 master=35095 | 1500 | 0 | 2.29 | 2.29 | 3.68 |
| reload-ossl35-pq-r500-t2 | 151.2 | reload n=5 master=35095 | 1500 | 0 | 2.27 | 2.29 | 3.9 |
| reload-ossl35-pq-r500-t2 | 181.2 | reload n=6 master=35095 | 1500 | 0 | 2.29 | 2.29 | 2.86 |
| reload-ossl35-pq-r500-t2 | 211.2 | reload n=7 master=35095 | 1500 | 0 | 2.31 | 2.29 | 2.98 |
| reload-ossl35-pq-r500-t2 | 241.2 | reload n=8 master=35095 | 1500 | 0 | 2.33 | 2.29 | 3.6 |
| reload-ossl35-pq-r500-t2 | 271.2 | reload n=9 master=35095 | 1500 | 0 | 2.29 | 2.29 | 3.98 |
| reload-ossl35-pq-r500-t3 | 31.4 | reload n=1 master=39358 | 1500 | 0 | 2.28 | 2.28 | 3.0 |
| reload-ossl35-pq-r500-t3 | 61.5 | reload n=2 master=39358 | 1500 | 0 | 2.29 | 2.28 | 3.98 |
| reload-ossl35-pq-r500-t3 | 91.5 | reload n=3 master=39358 | 1500 | 0 | 2.28 | 2.28 | 3.97 |
| reload-ossl35-pq-r500-t3 | 121.5 | reload n=4 master=39358 | 1500 | 0 | 2.32 | 2.28 | 3.71 |
| reload-ossl35-pq-r500-t3 | 151.5 | reload n=5 master=39358 | 1500 | 0 | 2.29 | 2.28 | 5.04 |
| reload-ossl35-pq-r500-t3 | 181.5 | reload n=6 master=39358 | 1500 | 0 | 2.28 | 2.28 | 3.22 |
| reload-ossl35-pq-r500-t3 | 211.5 | reload n=7 master=39358 | 1500 | 0 | 2.28 | 2.28 | 5.02 |
| reload-ossl35-pq-r500-t3 | 241.5 | reload n=8 master=39358 | 1500 | 0 | 2.27 | 2.28 | 2.96 |
| reload-ossl35-pq-r500-t3 | 271.5 | reload n=9 master=39358 | 1500 | 0 | 2.3 | 2.28 | 4.03 |
| swap-fast-rollback-ossl30-classical-r500-t1 | 31.2 | usr2 old_master=45903 | 1500 | 0 | 2.29 | 2.25 | 2.6 |
| swap-fast-rollback-ossl30-classical-r500-t1 | 37.7 | winch old_master=45903 | 1500 | 0 | 2.3 | 2.25 | 3.0 |
| swap-fast-rollback-ossl30-classical-r500-t1 | 67.7 | hup old_master=45903 (old workers respawn with old binary+config) | 1500 | 0 | 2.27 | 2.25 | 3.25 |
| swap-fast-rollback-ossl30-classical-r500-t1 | 70.7 | quit new_master=46211 | 1500 | 0 | 2.17 | 2.25 | 2.83 |
| swap-fast-rollback-ossl30-classical-r500-t2 | 31.7 | usr2 old_master=46926 | 1500 | 0 | 2.36 | 2.27 | 3.84 |
| swap-fast-rollback-ossl30-classical-r500-t2 | 38.2 | winch old_master=46926 | 1500 | 0 | 2.3 | 2.27 | 2.55 |
| swap-fast-rollback-ossl30-classical-r500-t2 | 68.2 | hup old_master=46926 (old workers respawn with old binary+config) | 1500 | 0 | 2.3 | 2.27 | 2.76 |
| swap-fast-rollback-ossl30-classical-r500-t2 | 71.2 | quit new_master=47243 | 1500 | 0 | 2.18 | 2.27 | 2.41 |
| swap-fast-rollback-ossl30-classical-r500-t3 | 31.2 | usr2 old_master=47943 | 1500 | 0 | 2.35 | 2.26 | 3.06 |
| swap-fast-rollback-ossl30-classical-r500-t3 | 37.7 | winch old_master=47943 | 1500 | 0 | 2.27 | 2.26 | 3.03 |
| swap-fast-rollback-ossl30-classical-r500-t3 | 67.7 | hup old_master=47943 (old workers respawn with old binary+config) | 1500 | 0 | 2.27 | 2.26 | 3.68 |
| swap-fast-rollback-ossl30-classical-r500-t3 | 70.7 | quit new_master=48248 | 1500 | 0 | 2.17 | 2.26 | 3.1 |
| swap-ossl30-classical-r500-t1 | 31.9 | usr2 old_master=41491 | 1500 | 0 | 2.27 | 2.27 | 3.53 |
| swap-ossl30-classical-r500-t1 | 38.4 | winch old_master=41491 | 1500 | 0 | 2.26 | 2.27 | 3.81 |
| swap-ossl30-classical-r500-t1 | 48.4 | quit old_master=41491 | 1500 | 0 | 2.26 | 2.27 | 3.72 |
| swap-ossl30-classical-r500-t1 | 93.4 | usr2 old_master=41803 (naive) | 1500 | 0 | 2.29 | 2.27 | 2.58 |
| swap-ossl30-classical-r500-t1 | 140.0 | usr2 old_master=41803 | 1500 | 0 | 2.27 | 2.27 | 3.75 |
| swap-ossl30-classical-r500-t1 | 146.5 | winch old_master=41803 | 1500 | 0 | 2.2 | 2.27 | 3.61 |
| swap-ossl30-classical-r500-t1 | 156.5 | quit old_master=41803 | 1500 | 0 | 2.2 | 2.27 | 3.1 |
| swap-ossl30-classical-r500-t2 | 31.7 | usr2 old_master=42965 | 1500 | 0 | 2.34 | 2.29 | 5.85 |
| swap-ossl30-classical-r500-t2 | 38.2 | winch old_master=42965 | 1500 | 0 | 2.3 | 2.29 | 3.12 |
| swap-ossl30-classical-r500-t2 | 48.2 | quit old_master=42965 | 1500 | 0 | 2.31 | 2.29 | 3.43 |
| swap-ossl30-classical-r500-t2 | 93.3 | usr2 old_master=43301 (naive) | 1500 | 0 | 2.29 | 2.29 | 3.83 |
| swap-ossl30-classical-r500-t2 | 139.8 | usr2 old_master=43301 | 1500 | 0 | 2.32 | 2.29 | 3.87 |
| swap-ossl30-classical-r500-t2 | 146.4 | winch old_master=43301 | 1500 | 0 | 2.2 | 2.29 | 3.57 |
| swap-ossl30-classical-r500-t2 | 156.4 | quit old_master=43301 | 1500 | 0 | 2.19 | 2.29 | 3.37 |
| swap-ossl30-classical-r500-t3 | 31.1 | usr2 old_master=44468 | 1500 | 0 | 2.37 | 2.29 | 2.92 |
| swap-ossl30-classical-r500-t3 | 37.6 | winch old_master=44468 | 1500 | 0 | 2.27 | 2.29 | 3.56 |
| swap-ossl30-classical-r500-t3 | 47.6 | quit old_master=44468 | 1500 | 0 | 2.28 | 2.29 | 3.5 |
| swap-ossl30-classical-r500-t3 | 92.7 | usr2 old_master=44776 (naive) | 1500 | 0 | 2.3 | 2.29 | 3.19 |
| swap-ossl30-classical-r500-t3 | 139.2 | usr2 old_master=44776 | 1500 | 0 | 2.38 | 2.29 | 3.21 |
| swap-ossl30-classical-r500-t3 | 145.8 | winch old_master=44776 | 1500 | 0 | 2.18 | 2.29 | 3.46 |
| swap-ossl30-classical-r500-t3 | 155.8 | quit old_master=44776 | 1500 | 0 | 2.18 | 2.29 | 2.67 |

