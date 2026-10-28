#!/usr/bin/env bash
# Surface regression; reports retain each client exit status, including timeout.
set +e
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
WS=${WAYDROID_A17_WS:-$(dirname "$REPO")}
M=$WS/nvidia/waydroid-nvidia/nvidia-prolapse/media
OUT=${1:-/tmp/surface-evidence/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT" || exit 1
OUT=$(realpath "$OUT")
if [[ ${WD_GUEST_LOCKED:-0} != 1 ]]; then
    exec flock /tmp/wd-guest.lock env WD_GUEST_LOCKED=1 "$0" "$OUT"
fi
# Keep lxc-attach away from regular log descriptors (it chmods/chowns them).
guest() {
    "$HERE/guest.sh" "$@" 2>&1 | cat
    return "${PIPESTATUS[0]}"
}
G=guest
SUDO=(sudo ${SUDO_ASKPASS:+-A})
SCRATCH=/data/local/tmp/c2-surface-$$
HOST=$HOME/.local/share/waydroid/data/local/tmp/c2-surface-$$
cleanup() { "$G" "rm -rf '$SCRATCH'" >>"$OUT/cleanup.log" 2>&1; }
trap cleanup EXIT
make -C "$M" c2-surface-smoke >"$OUT/build.log" 2>&1 || exit 1
TMP=$(mktemp -d) || exit 1
S=(-f lavfi -i testsrc2=size=1280x720:rate=30 -t 2)
rc=0
for c in avc hevc vp9 av1; do
    case $c in
        avc) args=(-c:v libx264 -pix_fmt yuv420p);;
        hevc) args=(-c:v libx265 -preset ultrafast -pix_fmt yuv420p -tag:v hvc1);;
        vp9) args=(-c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 2M);;
        av1) args=(-c:v libsvtav1 -preset 12 -pix_fmt yuv420p);;
    esac
    ffmpeg -loglevel error -y "${S[@]}" "${args[@]}" "$TMP/smoke-$c.mp4" >"$OUT/generate-$c.log" 2>&1 || { rc=1; break; }
done
if [[ $rc == 0 ]]; then
    "$G" "mkdir -p '$SCRATCH' && chmod 755 '$SCRATCH'" || rc=1
    "${SUDO[@]}" cp "$M/out/android/c2_surface_smoke" "$TMP"/*.mp4 "$HOST/" || rc=1
fi
rm -rf "$TMP"
[[ $rc == 0 ]] || exit 1
"$G" "chmod 755 '$SCRATCH/c2_surface_smoke'; chmod 644 '$SCRATCH/'*.mp4" || exit 1
printf 'codec\texit_code\n' >"$OUT/exit-codes.tsv"
for c in avc hevc vp9 av1; do
    "$G" "cd '$SCRATCH' && timeout -s KILL 90 ./c2_surface_smoke smoke-$c.mp4 c2.nvprolapse.$c.decoder" >"$OUT/$c.log" 2>&1
    status=$?
    printf '%s\t%s\n' "$c" "$status" | tee -a "$OUT/exit-codes.tsv"
    [[ $status == 0 ]] || rc=1
done
exit "$rc"
