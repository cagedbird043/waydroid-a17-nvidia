#!/usr/bin/env bash
# Hardware codec regression inside the running guest, through MediaCodec:
#   decode: c2_smoke on 2 s 720p H.264/HEVC/VP9/AV1 clips  -> expects "N frames, ..., 0 bad buffers"
#   encode: c2_enc_smoke on 60 NV12 frames per encoder      -> output decoded on the host with FFmpeg
# Builds the guest clients first when missing (make c2-smoke c2-enc-smoke in nvidia-prolapse/media).
# Needs sudo (SUDO_ASKPASS honoured), ffmpeg with libx264/libx265/libvpx/libsvtav1 on the host.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
WS=${WAYDROID_A17_WS:-$(dirname "$REPO")}
M=$WS/nvidia/waydroid-nvidia/nvidia-prolapse/media
D=$HOME/.local/share/waydroid/data/local/tmp     # = /data/local/tmp in the guest
SUDO=(sudo ${SUDO_ASKPASS:+-A})
G="$HERE/guest.sh"
for c in c2_smoke c2_enc_smoke; do
    [ -x "$M/out/android/$c" ] || { echo "codec-smoke: build $M/out/android/$c first (make ${c//_/-})" >&2; exit 1; }
done
T=$(mktemp -d)
trap 'rm -rf "$T"; "$G" "cd /data/local/tmp && rm -f smoke-* c2_smoke c2_enc_smoke" >/dev/null 2>&1 || true' EXIT
S=(-f lavfi -i testsrc2=size=1280x720:rate=30 -t 2)   # short clips: long AV1/HEVC software encodes take minutes
ffmpeg -loglevel error -y "${S[@]}" -c:v libx264 -pix_fmt yuv420p "$T/smoke-avc.mp4"
ffmpeg -loglevel error -y "${S[@]}" -c:v libx265 -preset ultrafast -pix_fmt yuv420p -tag:v hvc1 "$T/smoke-hevc.mp4" 2>/dev/null
ffmpeg -loglevel error -y "${S[@]}" -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 2M "$T/smoke-vp9.mp4"
ffmpeg -loglevel error -y "${S[@]}" -c:v libsvtav1 -preset 12 -pix_fmt yuv420p "$T/smoke-av1.mp4" 2>/dev/null
ffmpeg -loglevel error -y "${S[@]}" -pix_fmt nv12 -f rawvideo "$T/smoke-in.nv12"
"${SUDO[@]}" cp "$T"/smoke-* "$M/out/android/c2_smoke" "$M/out/android/c2_enc_smoke" "$D/"
# the guest's /data/local/tmp is not readable by the host user, so globs there must expand in the guest
"$G" 'cd /data/local/tmp && chmod 755 c2_smoke c2_enc_smoke && chmod 644 smoke-*
for c in avc hevc vp9 av1; do ./c2_smoke smoke-$c.mp4 2>&1 | tail -1; done
for c in "avc video/avc" "hevc video/hevc" "av1 video/av01"; do set -- $c
    ./c2_enc_smoke c2.nvprolapse.$1.encoder $2 1280 720 smoke-in.nv12 smoke-out-$1 3000 2>&1 | tail -1; done'
for c in avc hevc av1; do
    "${SUDO[@]}" cat "$D/smoke-out-$c" > "$T/out-$c"
done
# AV1: the first codec-config buffer is an av1C record (4 bytes + sequence header OBU), not part of the stream
python3 -I -c 'import sys; d=open(sys.argv[1],"rb").read(); open(sys.argv[2],"wb").write(d[4+2+d[5]:])' "$T/out-av1" "$T/out-av1.obu"
rc=0
for f in out-avc out-hevc out-av1.obu; do
    o=(); [[ $f == *.obu ]] && o=(-f obu)
    errs=$(ffmpeg -v error "${o[@]}" -i "$T/$f" -f null - 2>&1 | wc -l)
    info=$(ffprobe -v error "${o[@]}" -count_frames -show_entries stream=codec_name,profile,nb_read_frames -of csv=p=0 "$T/$f")
    echo "host decode $f: $info, $errs errors"
    [ "$errs" = 0 ] || rc=1
done
exit $rc
