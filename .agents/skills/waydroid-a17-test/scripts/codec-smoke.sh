#!/usr/bin/env bash
# Strict MediaCodec ByteBuffer regression. CODEC_SMOKE_FAULT exercises the failure gates.
set +e
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
if [[ ${WD_GUEST_LOCKED:-0} != 1 ]]; then exec flock /tmp/wd-guest.lock env WD_GUEST_LOCKED=1 "$0" "$@"; fi
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
WS=${WAYDROID_A17_WS:-$(dirname "$REPO")}
M=$WS/nvidia/waydroid-nvidia/nvidia-prolapse/media
D=$HOME/.local/share/waydroid/data/local/tmp
G=$HERE/guest.sh
SUDO=(sudo ${SUDO_ASKPASS:+-A})
T=${CODEC_SMOKE_OUT:-$(mktemp -d)}
mkdir -p "$T" || exit 1
rc=0
fail() { echo "FAIL: $*"; rc=1; }
run_client() {
    local id=$1 cmd=$2 status
    # lxc-attach may chown/fchmod its stdout; keep the evidence file behind a pipe.
    "$G" "cd /data/local/tmp; $cmd" 2>&1 | tee "$T/$id.log"
    status=${PIPESTATUS[0]}
    printf '%s\n' "$status" >"$T/$id.exit"
    [[ $status == 0 ]] || fail "$id exit=$status"
}
S=(-f lavfi -i testsrc2=size=1280x720:rate=30 -frames:v 60)
for c in avc hevc vp9 av1; do
    case $c in
      avc) args=(-c:v libx264);;
      hevc) args=(-c:v libx265 -preset ultrafast -tag:v hvc1);;
      vp9) args=(-c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 2M);;
      av1) args=(-c:v libsvtav1 -preset 12);;
    esac
    ffmpeg -v error -y "${S[@]}" "${args[@]}" -pix_fmt yuv420p "$T/smoke-$c.mp4" >"$T/generate-$c.log" 2>&1 || exit 1
done
ffmpeg -v error -y "${S[@]}" -pix_fmt nv12 -f rawvideo "$T/smoke-in.nv12" >"$T/generate-input.log" 2>&1 || exit 1
"${SUDO[@]}" cp "$T"/smoke-* "$M/out/android/c2_smoke" "$M/out/android/c2_enc_smoke" "$D/" || exit 1
"$G" 'cd /data/local/tmp; chmod 755 c2_smoke c2_enc_smoke; chmod 644 smoke-*' || exit 1
for c in avc hevc vp9 av1; do
    name=c2.nvprolapse.$c.decoder
    [[ ${CODEC_SMOKE_FAULT:-} == wrong-name && $c == avc ]] && name=c2.nvprolapse.nonexistent.decoder
    command="./c2_smoke smoke-$c.mp4 $name"
    [[ ${CODEC_SMOKE_FAULT:-} == client-failure && $c == hevc ]] && command='exit 42'
    [[ ${CODEC_SMOKE_FAULT:-} == bad-buffer && $c == avc ]] && command+=' bad-buffer'
    run_client decode-$c "$command"
    [[ $(grep -Ec '^video/[^:]+: 60 frames, 1280x720, 0 bad buffers$' "$T/decode-$c.log") == 1 ]] || fail "decode-$c frame/buffer assertion"
done
for mode in flush destroy error; do
    run_client "$mode" "./c2_smoke smoke-avc.mp4 c2.nvprolapse.avc.decoder $mode"
    case $mode in
      flush) grep -q '^flush: OK$' "$T/$mode.log" && grep -q '60 frames, 1280x720, 0 bad buffers$' "$T/$mode.log" || fail flush;;
      destroy) grep -q '^destroy: OK' "$T/$mode.log" || fail destroy;;
      error) grep -q '^error: rejected' "$T/$mode.log" || fail error;;
    esac
done
for c in avc hevc av1; do
    mime=video/$c; [[ $c == av1 ]] && mime=video/av01
    run_client encode-$c "./c2_enc_smoke c2.nvprolapse.$c.encoder $mime 1280 720 smoke-in.nv12 smoke-out-$c 3000; status=\$?; chmod 644 smoke-out-$c; exit \$status"
    grep -Eq "^c2.nvprolapse.$c.encoder: 60 pictures in, 60 out," "$T/encode-$c.log" || fail "encode-$c counts"
    "${SUDO[@]}" cat "$D/smoke-out-$c" >"$T/out-$c" || fail "copy-$c"
done
python3 -I -c 'import sys;d=open(sys.argv[1],"rb").read();assert len(d)>6;open(sys.argv[2],"wb").write(d[6+d[5]:])' "$T/out-av1" "$T/out-av1.obu" || fail av1-config
if [[ ${CODEC_SMOKE_FAULT:-} == truncated ]]; then truncate -s 100 "$T/out-avc"; fi
for f in out-avc out-hevc out-av1.obu; do
    opts=(); [[ $f == *.obu ]] && opts=(-f obu)
    ffmpeg -v error -xerror "${opts[@]}" -i "$T/$f" -f null - >"$T/$f.ffmpeg.log" 2>&1
    status=$?; echo "$status" >"$T/$f.ffmpeg.exit"
    [[ $status == 0 && ! -s $T/$f.ffmpeg.log ]] || fail "$f FFmpeg"
    ffprobe -v error "${opts[@]}" -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$T/$f" >"$T/$f.frames" 2>"$T/$f.ffprobe.log"
    status=$?; echo "$status" >"$T/$f.ffprobe.exit"
    [[ $status == 0 && $(cat "$T/$f.frames") == 60 && ! -s $T/$f.ffprobe.log ]] || fail "$f ffprobe frames"
done
echo "$rc" >"$T/result.exit"
echo "codec-smoke: exit=$rc evidence=$T"
exit "$rc"
