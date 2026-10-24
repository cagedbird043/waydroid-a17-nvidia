#!/usr/bin/env bash
# HWUI benchmark in the running Waydroid session: scrolling frame times in Settings' all-apps list and app cold starts.
# Usage: scripts/bench-hwui.sh LABEL [ROUNDS]   (needs sudo; SUDO_ASKPASS is used when set)
# Output: logs/bench-hwui-LABEL.txt (raw gfxinfo per round and cold-start times)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LABEL=${1:?label}
ROUNDS=${2:-3}
OUT=$ROOT/logs/bench-hwui-$LABEL.txt
SUDO=(sudo ${SUDO_ASKPASS:+-A})

"${SUDO[@]}" waydroid shell -- sh -c '
rounds=$1
echo "renderer $(getprop debug.hwui.renderer)"
size=$(wm size | sed -n "s/.*: //p" | tail -1); w=${size%x*}; h=${size#*x}
x=$((w / 2)); y0=$((h * 85 / 100)); y1=$((h * 20 / 100))
for r in $(seq 1 "$rounds"); do
    am force-stop com.android.settings
    am start -W -a android.settings.MANAGE_ALL_APPLICATIONS_SETTINGS >/dev/null
    sleep 3
    dumpsys gfxinfo com.android.settings reset >/dev/null
    for i in $(seq 1 30); do
        if [ $((i % 2)) = 1 ]; then input swipe "$x" "$y0" "$x" "$y1" 200; else input swipe "$x" "$y1" "$x" "$y0" 200; fi
        sleep 0.4
        # framestats keeps the last 120 frames; one swipe renders fewer, so no frame is lost between dumps
        dumpsys gfxinfo com.android.settings framestats | sed -n "/---PROFILEDATA---/,/---PROFILEDATA---/p" | grep -E "^(Flags|0|1)," | sed "s/^/FS,/"
    done
    sleep 1
    echo "== scroll round $r"
    dumpsys gfxinfo com.android.settings | grep -E "^(Total frames rendered|Janky frames|[0-9]+th (gpu )?percentile)"
done
for pkg in com.android.calculator2 com.android.deskclock org.lineageos.jelly me.weishu.kernelsu com.brouken.player; do
    comp=$(cmd package resolve-activity --brief "$pkg" | tail -1)
    for r in $(seq 1 "$rounds"); do
        t=$(am start -S -W -n "$comp" | sed -n "s/^TotalTime: //p")
        echo "coldstart $pkg $t"
        sleep 2
    done
    am force-stop "$pkg"
done
' sh "$ROUNDS" | tee "$OUT"
