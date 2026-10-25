#!/usr/bin/env bash
# Restart the Waydroid session detached from the caller (a foreground `waydroid session start` never returns)
# and wait until Android is up. Log: /tmp/wd-session-mw.log
set -uo pipefail
waydroid session stop >/dev/null 2>&1
sleep 3
: > /tmp/wd-session-mw.log
setsid -f sh -c 'waydroid session start > /tmp/wd-session-mw.log 2>&1'
for _ in $(seq 1 90); do
    grep -qE 'ready|OSError' /tmp/wd-session-mw.log && break
    sleep 2
done
grep -E 'ready|OSError' /tmp/wd-session-mw.log || { echo 'session-restart: no ready line after 180 s' >&2; exit 1; }
grep -q OSError /tmp/wd-session-mw.log && exit 1
sleep 20   # services (Codec2, SurfaceFlinger clients) settle after "ready"
