#!/bin/bash

set -euo pipefail

app_path="${1:-}"
[[ -n "$app_path" && -d "$app_path" ]] || {
  echo "runtime smoke: LaunchDeck.app path is required" >&2
  exit 64
}

binary="$app_path/Contents/MacOS/LaunchDeck"
[[ -x "$binary" ]] || {
  echo "runtime smoke: executable is missing" >&2
  exit 1
}

for cycle in 1 2 3; do
  log_file="$(mktemp /tmp/launchdeck-runtime-smoke.XXXXXX)"
  started_at="$(python3 -c 'import time; print(time.monotonic_ns())')"
  "$binary" >"$log_file" 2>&1 &
  app_pid=$!

  for _ in {1..20}; do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      echo "runtime smoke: process exited during cold launch cycle ${cycle}" >&2
      sed -n '1,120p' "$log_file" >&2
      rm -f "$log_file"
      exit 1
    fi
    sleep 0.1
  done

  resident_kb="$(ps -o rss= -p "$app_pid" | tr -d ' ')"
  ended_at="$(python3 -c 'import time; print(time.monotonic_ns())')"
  elapsed_ms=$(( (ended_at - started_at) / 1000000 ))
  echo "runtime smoke: cycle ${cycle} healthy for ${elapsed_ms}ms rss=${resident_kb:-unknown}KB"
  kill "$app_pid"
  wait "$app_pid" || true
  rm -f "$log_file"
done
