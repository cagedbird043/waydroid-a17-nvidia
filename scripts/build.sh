#!/usr/bin/env bash
# Run an Android build command inside the build container.
# Usage: scripts/build.sh <lunch-target> <m args...>     e.g. scripts/build.sh lineage_waydroid_x86_64-bp4a-userdebug vendorimage
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
target=$1; shift
jobs=${WAYDROID_BUILD_JOBS:-4}
memory=${WAYDROID_BUILD_MEMORY:-32g}
cpuset=${WAYDROID_BUILD_CPUSET:-$(python3 -c 'import os,sys; print(",".join(map(str, sorted(os.sched_getaffinity(0))[-int(sys.argv[1]):])))' "$jobs")}
# Soong bootstrap forwards these Go runtime controls through its clean environment.
# The Go limit is a soft runtime target, not an RSS cap; the cgroup remains the hard limit.
# Override with WAYDROID_BUILD_GOMEMLIMIT and WAYDROID_BUILD_GOGC.
mkdir -p "$ROOT/ccache"
exec podman run --rm --userns=keep-id --network=none --hostname=wd-a17-build \
    --cpus="${WAYDROID_BUILD_CPUS:-$jobs}" --memory="$memory" --memory-swap="$memory" \
    -v "$ROOT:$ROOT" -w "$ROOT/src" \
    -e CC_WRAPPER=/usr/bin/ccache -e CXX_WRAPPER=/usr/bin/ccache \
    -e CCACHE_DIR="$ROOT/ccache" -e CCACHE_MAXSIZE=60G \
    -e SOONG_NINJA="${WAYDROID_BUILD_EXECUTOR:-ninja}" \
    -e GOMEMLIMIT="${WAYDROID_BUILD_GOMEMLIMIT:-10GiB}" \
    -e GOGC="${WAYDROID_BUILD_GOGC:-10}" \
    -e TARGET_ARGS="$*" -e LUNCH_TARGET="$target" -e BUILD_JOBS="$jobs" \
    localhost/waydroid-a17-build \
    taskset -c "$cpuset" nice -n 10 ionice -c 3 bash -c '
        report_memory() {
            local peak event count
            if read -r peak < /sys/fs/cgroup/memory.peak; then
                printf "Build cgroup memory peak: %s bytes\n" "$peak" >&2
            fi
            while read -r event count; do
                case "$event" in
                    oom|oom_kill) printf "Build cgroup %s: %s\n" "$event" "$count" >&2 ;;
                esac
            done < /sys/fs/cgroup/memory.events
        }
        trap report_memory EXIT
        source build/envsetup.sh >/dev/null && lunch "$LUNCH_TARGET" && m -j"$BUILD_JOBS" $TARGET_ARGS
    '
