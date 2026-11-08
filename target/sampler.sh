#!/usr/bin/env bash
# Thin wrapper (kept so existing scripts and pid handling work): see sampler.py.
exec python3 "$(dirname "$0")/sampler.py" "$@"
