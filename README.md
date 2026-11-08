# pqc-bench-nginx-swap — Phase 7 of [pqc-bench](https://github.com/asifmahbubnaeem/pqc-bench): swapping nginx onto a PQ-capable OpenSSL, under live load

**Question:** if you move a running nginx from the distro OpenSSL to one that can do
X25519MLKEM768, what does it cost operationally — build, footprint, memory, CPU — and
can you do the swap (and roll it back) without dropping traffic?

## Arms

| | nginx | OpenSSL | TLS groups offered | cert |
|---|---|---|---|---|
| **A** `ossl30` | 1.28.0 | 3.0.13 (Ubuntu 24.04, shared) | X25519, P-256 | ECDSA P-256 |
| **B** `ossl35` | 1.28.0, identical configure flags | 3.5.2 (compiled in via `--with-openssl`) | X25519MLKEM768, X25519, P-256 | ECDSA P-256 |

Same nginx source and flags; only OpenSSL differs. Same classical cert in both: this is the
KEM-first migration that production can ship today. Both binaries share one `--prefix`
(`/opt/nginx`), which is what makes a live binary swap possible.

## Scenarios

| # | Scenario | What happens | Measures |
|---|---|---|---|
| 0 | `build` / `footprint` | build both arms, timed | build time, binary size, TLS code incl. shared libs |
| 1 | `idle` | each arm idle 60 s | baseline RSS (master / workers) |
| 2 | `reload` | 9× `nginx -s reload`, 30 s apart, under load | errors + p99 in the 3 s after each reload |
| 3 | `swap` | A→B live (`USR2`→`WINCH`→`QUIT`), then a **naive rollback** (binary only, PQ config left in place), then the correct rollback | errors / latency per signal, PQ share over time, RSS with two masters |
| 4 | `swap-fast-rollback` | A→B, then roll back *while the old master is alive* (`HUP` old, `QUIT` new) | same |
| 5 | `soak` | 10 min of fresh full handshakes per arm | RSS slope (MB/h) — leak check |
| 6 | ladder | 500 / 1000 / 2000 handshakes/s × {A classical, B classical, B pq} | CPU busy %: OpenSSL upgrade cost vs ML-KEM cost, separately |

Every connection is a full TLS 1.3 handshake (no keep-alive, no resumption, session
cache off). The load generator is open-loop, so a server stall shows up as latency and
errors instead of quietly reducing the offered load. Go's default client offers
X25519MLKEM768 + X25519 (like current browsers), so the same client negotiates PQ on B and
falls back to X25519 on A. nginx logs `$ssl_curve` and `$pid` per request; the response
carries `X-Worker-Pid`, so every request is attributable to a worker generation.

Already confirmed in the local dry run: **the PQ config is fatal on arm A**
(`SSL_CTX_set1_curves_list(... X25519MLKEM768 ...) failed`). Rolling back the binary
without reverting the config makes the new master exit at startup; the old one keeps
serving. Scenario 3 measures that path under load.

## Layout

```
pqc-bench-nginx-swap/
  terraform/          2× Ubuntu 24.04 arm64 (target c7g.large, loadgen c7g.xlarge), same AZ, cluster PG
  target/             build-nginx.sh, make-conf.sh, scenario.sh, sampler.sh, footprint.sh
  loadgen/            main.go (Go 1.24, stdlib only) + prebuilt pq-loadgen-linux-arm64
  run.sh              orchestrator (runs from your laptop over ssh)
  run-all.sh          full matrix, resumable
  analyze.py          summary.md + per-run timeline.png
  results/            created by the runs
```

## Runbook

```bash
# 0. infra (~2 min). Use the same key pair as earlier phases.
cd terraform
cp terraform.tfvars.example terraform.tfvars   # key_name + your IP/32 (curl -s ifconfig.me)
terraform init && terraform apply
eval "$(terraform output -raw env)"
export SSH_KEY=~/.ssh/<your-key>.pem
cd ..

# 1. wait ~1 min for user-data, then
./run.sh deploy
./run.sh build          # ~5–8 min on c7g.large (OpenSSL compile dominates arm B)

# 2. smoke test (~1 min) before the full matrix
WARM=5 RELOADS=2 RELOAD_EVERY=5 ./run.sh reload ossl35 pq 200 smoke
cat results/reload-ossl35-pq-r200-tsmoke/loadgen.stderr

# 3. full matrix (~80 min, resumable — rerun the same command after any interruption)
./run-all.sh 2>&1 | tee results/run-all.log

# 4. tear down
cd terraform && terraform destroy
```

Cost: ~$0.22/h for both instances → under $1 for the whole phase.

Laptop needs: `ssh`, `terraform`, `python3` with `pandas numpy matplotlib`.
Go is only needed to rebuild the loadgen
(`cd loadgen && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o pq-loadgen-linux-arm64 .`).

If ssh to EC2 times out from home, your ISP is blocking AWS on port 22 again; use the hotspot.

## Reading the output

`results/summary.md` has four tables: build/footprint, idle memory, runs under load, and
an event table (requests, errors, p99 and max latency in the 3 s after every signal, next to
that run's quiet p99). Each run directory has `timeline.png`: requests/s and errors, p50/p99
latency, % of handshakes on X25519MLKEM768, and nginx RSS, with signals as vertical lines
and two-master periods shaded.
