#!/usr/bin/env bash
# Run an Android build command inside the build container.
# Usage: scripts/build.sh <lunch-target> <m args...>     e.g. scripts/build.sh lineage_waydroid_x86_64-bp4a-userdebug vendorimage
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
target=$1; shift
mkdir -p "$ROOT/ccache"
exec podman run --rm --userns=keep-id --network=none --hostname=wd-a17-build \
    -v "$ROOT:$ROOT" -w "$ROOT/src" \
    -e CC_WRAPPER=/usr/bin/ccache -e CXX_WRAPPER=/usr/bin/ccache \
    -e CCACHE_DIR="$ROOT/ccache" -e CCACHE_MAXSIZE=60G \
    -e TARGET_ARGS="$*" -e LUNCH_TARGET="$target" \
    localhost/waydroid-a17-build \
    bash -c 'source build/envsetup.sh >/dev/null && lunch "$LUNCH_TARGET" && m $TARGET_ARGS'
