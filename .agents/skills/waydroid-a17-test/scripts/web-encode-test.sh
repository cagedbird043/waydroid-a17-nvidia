#!/usr/bin/env bash
# Open scripts/web/index.html in the guest's Chrome and print which hardware encoders the service opened.
# The page must be a secure context for WebCodecs, so it is served as http://localhost:8765 inside the guest:
# a host HTTP server on waydroid0 plus a toybox nc forwarder 127.0.0.1:8765 -> host (iptables nat is absent).
# The page shows its own results; read them from a screenshot of the Chrome window.
# Usage: web-encode-test.sh [seconds to wait, default 45]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
G="$HERE/guest.sh"
HOST=$(ip -4 -o addr show waydroid0 | awk '{sub(/\/.*/, "", $4); print $4}')
python3 -m http.server 8765 --bind "$HOST" --directory "$HERE/web" >/dev/null 2>&1 &
srv=$!
cleanup() {
    kill $srv 2>/dev/null || true
    "$G" "pkill -f 'nc -s 127.0.0.1 -p 8765'" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 1
"$G" "setsid toybox nc -s 127.0.0.1 -p 8765 -L toybox nc $HOST 8765 </dev/null >/dev/null 2>&1 & sleep 1; logcat -c"
waydroid app intent android.intent.action.VIEW "http://localhost:8765/?t=$(date +%s)" >/dev/null 2>&1
sleep "${1:-45}"
"$G" "logcat -d -s nvc2-enc | grep 'encoder:'" || echo 'web-encode-test: no nvc2-enc lines: Chrome used software encoders' >&2
