#!/usr/bin/env bash
# Restart the Waydroid session detached from the caller (a foreground `waydroid session start` never returns)
# and wait until Android is up. Log: /tmp/wd-session-mw.log
set -uo pipefail
waydroid session stop >/dev/null 2>&1
sleep 3
: > /tmp/wd-session-mw.log
# the detached shell must not keep the caller's stdout open, or `session-restart.sh | tail` never returns;
# it also closes every other inherited fd: under `flock /tmp/wd-guest.lock` the long-lived session would
# otherwise hold the guest lock forever and every later `flock` waits on it
setsid -f bash -c 'for f in /proc/self/fd/*; do n=${f##*/}; [ "$n" -gt 2 ] && eval "exec $n>&-"; done 2>/dev/null
    exec waydroid session start > /tmp/wd-session-mw.log 2>&1' </dev/null >/dev/null 2>&1
for _ in $(seq 1 90); do
    grep -qE 'ready|OSError' /tmp/wd-session-mw.log && break
    sleep 2
done
grep -E 'ready|OSError' /tmp/wd-session-mw.log || { echo 'session-restart: no ready line after 180 s' >&2; exit 1; }
grep -q OSError /tmp/wd-session-mw.log && exit 1
sleep 20   # services (Codec2, SurfaceFlinger clients) settle after "ready"
