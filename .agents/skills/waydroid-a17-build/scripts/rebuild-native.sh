#!/usr/bin/env bash
# Rebuild everything that links the Rust RM backend, in dependency order, inside localhost/nvk-native-a17:
#   Rust RM (x86_64 + i686) -> NVK (android, android32) -> nvrm GL (android, android32) -> nvc2-xmlgen
# nvrm records the Rust library it linked; the release gate refuses a bundle whose Rust library differs,
# so never ship a new libnv_bionic_native.so without this whole chain.
# Commit nvidia/waydroid-nvidia first: NVK/nvrm record the source head and refuse a dirty tree.
# Usage: rebuild-native.sh [--rust-only]      (logs: /tmp/nvk-build.log, /tmp/nvrm-build.log)
set -euo pipefail
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
WS=${WAYDROID_A17_WS:-$(dirname "$REPO")}
W=$WS/nvidia/waydroid-nvidia
cd "$W"
# The checkout is mounted at /work: the Mesa worktrees, meson build trees and build records all store /work paths.
NDK=/work/build/hwcomposer-work/ndk/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/bin
run() {
    podman run --rm --userns=keep-id -v "$W:/work" -w /work -e HOME=/work/build/.buildenv-home \
        -e CARGO_HOME=/work/build/.buildenv-home/cargo -e PROLAPSE_ROOT=/work \
        -e CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$NDK/x86_64-linux-android33-clang" \
        -e CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$NDK/i686-linux-android33-clang" \
        localhost/nvk-native-a17 bash -c "$1"
}
[ -z "$(git status --porcelain --untracked-files=no)" ] || echo "rebuild-native: warning: tracked changes in $W (NVK/nvrm will refuse)" >&2

if [ "${1:-}" = --rust-only ]; then
    # quick iteration only: the result cannot be released (nvrm still points at the old library)
    run 'cargo build --offline --release --no-default-features --target-dir build/nv-rm-rust \
        --manifest-path nvidia-prolapse/driver-source/native/Cargo.toml --target x86_64-linux-android --target i686-linux-android'
    exit
fi
B=nvidia-prolapse/driver-source/native/mesa/build.py
# NVK's build drives the Rust RM build and writes build/nvk-*/rust-build.json, which nvrm requires
run "set -e; for t in android android32; do python3 $B --target \$t --rust-profile release -j 14; done" > /tmp/nvk-build.log 2>&1 \
    || { tail -20 /tmp/nvk-build.log; exit 1; }
run "set -e; for t in android android32; do python3 $B --gl --target \$t --skip-prepare --download-deps --rust-profile release -j 14; done" \
    > /tmp/nvrm-build.log 2>&1 || { tail -20 /tmp/nvrm-build.log; exit 1; }
rm -f nvidia-prolapse/media/out/android/nvc2-xmlgen
run "make -s -C nvidia-prolapse/media xmlgen-android NV_VIDEO_ANDROID_LIB='-L/work/build/nv-rm-rust/x86_64-linux-android/release -lnv_bionic_native'"
for t in android android32; do
    python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); print(sys.argv[2], "nvrm head", r["driver_source_head"][:12], "dirty", r["driver_source_dirty"], "rust", r["rust"]["sha256"][:12])' \
        "build/nvrm-$t/nvrm-build.json" "$t"
done
sha256sum build/nv-rm-rust/{x86_64,i686}-linux-android/release/libnv_bionic_native.so | cut -c1-12
