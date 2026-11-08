#!/usr/bin/env python3
"""
Once per second: nginx process counts and RSS, whole-host CPU busy %, and nginx-only CPU.

nginx_cpu_cores = CPU time (user+system) consumed by all nginx processes during the last
interval, in cores (1.0 = one full vCPU). It is computed per PID from /proc/<pid>/stat, so
kernel networking, sshd, and anything else on the host is excluded. A PID that appears
mid-interval contributes the ticks it accumulated since it started.

Usage: sampler.py OUT.csv   (runs until killed)
"""
import os
import sys
import time

TICK = os.sysconf("SC_CLK_TCK")
COLS = ("ts,procs,masters,workers,shutting_down,rss_kb_total,rss_kb_master_max,"
        "rss_kb_worker_max,cpu_busy_pct,nginx_cpu_cores")


def host_cpu():
    with open("/proc/stat") as f:
        v = list(map(int, f.readline().split()[1:9]))
    user, nice, system, idle, iowait, irq, softirq, steal = v
    busy = user + nice + system + irq + softirq + steal
    return busy, busy + idle + iowait


def nginx_procs():
    out = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                stat = f.read()
            comm = stat[stat.index("(") + 1:stat.rindex(")")]
            if comm != "nginx":
                continue
            fields = stat[stat.rindex(")") + 2:].split()
            ticks = int(fields[11]) + int(fields[12])        # utime + stime
            rss_kb = int(fields[21]) * os.sysconf("SC_PAGE_SIZE") // 1024
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace")
            out[int(pid)] = (ticks, rss_kb, cmd)
        except (FileNotFoundError, ProcessLookupError, ValueError, IndexError):
            continue
    return out


def main():
    path = sys.argv[1]
    with open(path, "w") as f:
        f.write(COLS + "\n")
    prev_busy, prev_total = host_cpu()
    prev = nginx_procs()
    prev_t = time.monotonic()
    while True:
        time.sleep(1)
        now = time.monotonic()
        busy, total = host_cpu()
        cur = nginx_procs()
        dt_wall = now - prev_t
        cpu = 100.0 * (busy - prev_busy) / (total - prev_total) if total > prev_total else 0.0
        d_ticks = sum(t - prev.get(pid, (0,))[0] for pid, (t, _, _) in cur.items())
        cores = d_ticks / TICK / dt_wall if dt_wall > 0 else 0.0
        masters = [r for (_, r, c) in cur.values() if "master process" in c]
        workers = [r for (_, r, c) in cur.values() if "worker process" in c]
        shutting = sum(1 for (_, _, c) in cur.values() if "shutting down" in c)
        row = (f"{time.time():.6f},{len(cur)},{len(masters)},{len(workers)},{shutting},"
               f"{sum(r for (_, r, _) in cur.values())},{max(masters, default=0)},"
               f"{max(workers, default=0)},{cpu:.1f},{cores:.3f}")
        with open(path, "a") as f:
            f.write(row + "\n")
        prev_busy, prev_total, prev, prev_t = busy, total, cur, now


if __name__ == "__main__":
    main()
