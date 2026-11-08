// pq-loadgen — open-loop TLS 1.3 load generator for pqc-bench Phase 7.
//
// Every request opens a fresh TCP connection and does a full TLS 1.3 handshake
// (no keep-alive, no session resumption), then one GET. Requests are scheduled at a
// fixed rate regardless of how long earlier ones take (open loop), so a server stall
// shows up as latency and errors instead of silently lowering the offered load.
//
// One CSV row per request:
//   start_ns, total_ms, tls_ms, status, worker_pid, error
// worker_pid comes from the X-Worker-Pid response header and shows which nginx worker
// generation served the request — that is how reloads and binary swaps become visible.
//
// Group selection (-groups):
//   default   Go's default list — X25519MLKEM768 first, then X25519 (like current browsers)
//   classical X25519, P-256 only
//   pq        X25519MLKEM768 only (fails against a server that can't do it)
package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptrace"
	"os"
	"os/signal"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

type result struct {
	start   time.Time
	totalMs float64
	tlsMs   float64
	status  int
	pid     string
	errCls  string
}

func classify(err error) string {
	if err == nil {
		return ""
	}
	s := err.Error()
	switch {
	case errors.Is(err, context.DeadlineExceeded), strings.Contains(s, "timeout"):
		return "timeout"
	case strings.Contains(s, "connection refused"):
		return "refused"
	case strings.Contains(s, "connection reset"):
		return "reset"
	case strings.Contains(s, "EOF"):
		return "eof"
	case strings.Contains(s, "tls:") || strings.Contains(s, "handshake"):
		return "tls"
	default:
		return "other:" + strings.ReplaceAll(s, ",", ";")
	}
}

func main() {
	target := flag.String("url", "https://127.0.0.1/", "target URL")
	rate := flag.Int("rate", 200, "new connections (requests) per second")
	dur := flag.Duration("duration", 60*time.Second, "test duration")
	timeout := flag.Duration("timeout", 5*time.Second, "per-request timeout (dial+TLS+response)")
	maxInflight := flag.Int("max-inflight", 5000, "cap on concurrent requests (overflow is recorded as 'dropped')")
	groups := flag.String("groups", "default", "default | classical | pq")
	out := flag.String("out", "loadgen.csv", "output CSV")
	flag.Parse()

	tlsCfg := &tls.Config{
		InsecureSkipVerify: true, // self-signed bench cert; we measure transport, not PKI
		MinVersion:         tls.VersionTLS13,
		ClientSessionCache: nil, // never resume
	}
	switch *groups {
	case "default":
	case "classical":
		tlsCfg.CurvePreferences = []tls.CurveID{tls.X25519, tls.CurveP256}
	case "pq":
		tlsCfg.CurvePreferences = []tls.CurveID{tls.X25519MLKEM768}
	default:
		fmt.Fprintln(os.Stderr, "unknown -groups", *groups)
		os.Exit(2)
	}

	f, err := os.Create(*out)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	w := bufio.NewWriterSize(f, 1<<20)
	fmt.Fprintln(w, "start_ns,total_ms,tls_ms,status,worker_pid,error")

	results := make(chan result, 65536)
	var wgWriter sync.WaitGroup
	wgWriter.Add(1)
	var nOK, nErr, nDropped atomic.Int64
	latencies := make([]float64, 0, *rate*int(dur.Seconds())+1)
	errCounts := map[string]int{}
	go func() {
		defer wgWriter.Done()
		for r := range results {
			fmt.Fprintf(w, "%d,%.3f,%.3f,%d,%s,%s\n", r.start.UnixNano(), r.totalMs, r.tlsMs, r.status, r.pid, r.errCls)
			if r.errCls == "" && r.status == 200 {
				latencies = append(latencies, r.totalMs)
			} else {
				k := r.errCls
				if k == "" {
					k = fmt.Sprintf("http_%d", r.status)
				}
				errCounts[k]++
			}
		}
	}()

	doOne := func(start time.Time) {
		tr := &http.Transport{
			TLSClientConfig:     tlsCfg,
			DisableKeepAlives:   true,
			ForceAttemptHTTP2:   false,
			TLSHandshakeTimeout: *timeout,
			DialContext:         (&net.Dialer{Timeout: *timeout}).DialContext,
		}
		defer tr.CloseIdleConnections()
		ctx, cancel := context.WithTimeout(context.Background(), *timeout)
		defer cancel()
		var tlsStart, tlsDone time.Time
		trace := &httptrace.ClientTrace{
			TLSHandshakeStart: func() { tlsStart = time.Now() },
			TLSHandshakeDone:  func(tls.ConnectionState, error) { tlsDone = time.Now() },
		}
		req, _ := http.NewRequestWithContext(httptrace.WithClientTrace(ctx, trace), "GET", *target, nil)
		resp, err := tr.RoundTrip(req)
		r := result{start: start}
		if err == nil {
			io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
			r.status = resp.StatusCode
			r.pid = resp.Header.Get("X-Worker-Pid")
		}
		r.totalMs = float64(time.Since(start).Microseconds()) / 1000
		if !tlsStart.IsZero() && !tlsDone.IsZero() {
			r.tlsMs = float64(tlsDone.Sub(tlsStart).Microseconds()) / 1000
		}
		r.errCls = classify(err)
		if err == nil && r.status == 200 {
			nOK.Add(1)
		} else {
			nErr.Add(1)
		}
		results <- r
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	sem := make(chan struct{}, *maxInflight)
	var wg sync.WaitGroup
	interval := time.Second / time.Duration(*rate)
	begin := time.Now()
	end := begin.Add(*dur)
	next := begin
	fmt.Fprintf(os.Stderr, "==> %s  rate=%d/s  duration=%s  groups=%s\n", *target, *rate, *dur, *groups)
	lastReport := begin

loop:
	for {
		now := time.Now()
		if now.After(end) {
			break
		}
		select {
		case <-stop:
			break loop
		default:
		}
		if now.Before(next) {
			time.Sleep(next.Sub(now))
		}
		start := next
		next = next.Add(interval)
		select {
		case sem <- struct{}{}:
			wg.Add(1)
			go func() {
				defer wg.Done()
				defer func() { <-sem }()
				doOne(start)
			}()
		default:
			nDropped.Add(1)
			results <- result{start: start, errCls: "dropped"}
		}
		if time.Since(lastReport) >= 10*time.Second {
			lastReport = time.Now()
			fmt.Fprintf(os.Stderr, "    t=%3.0fs ok=%d err=%d dropped=%d\n",
				time.Since(begin).Seconds(), nOK.Load(), nErr.Load(), nDropped.Load())
		}
	}
	wg.Wait()
	close(results)
	wgWriter.Wait()
	w.Flush()
	f.Close()

	sort.Float64s(latencies)
	pct := func(p float64) float64 {
		if len(latencies) == 0 {
			return 0
		}
		return latencies[int(p*float64(len(latencies)-1))]
	}
	fmt.Fprintf(os.Stderr, "==> done: ok=%d err=%d dropped=%d  p50=%.2fms p99=%.2fms p999=%.2fms  -> %s\n",
		nOK.Load(), nErr.Load(), nDropped.Load(), pct(0.5), pct(0.99), pct(0.999), *out)
	if len(errCounts) > 0 {
		fmt.Fprintf(os.Stderr, "    errors: %v\n", errCounts)
	}
}
