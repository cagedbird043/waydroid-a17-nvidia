#!/usr/bin/env bash
# Guest Chrome only; separate acknowledged logcat window and JSON for every case.
set +e
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
if [[ ${WD_GUEST_LOCKED:-0} != 1 ]]; then exec flock /tmp/wd-guest.lock env WD_GUEST_LOCKED=1 "$0" "$@"; fi
OUT=${WEB_ENCODE_OUT:-$(mktemp -d)}
exec python3 "$HERE/web-encode-server.py" --out "$OUT" --timeout "${1:-150}"
