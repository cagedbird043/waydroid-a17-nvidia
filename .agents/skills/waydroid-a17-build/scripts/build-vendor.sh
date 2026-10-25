#!/usr/bin/env bash
# Two-pass vendor build: the release gate requires the Codec2 service in the image to be byte-identical to the
# one in the native bundle, and the service is itself built in the A17 tree against that bundle's Rust library.
#   1. bundle with the fresh native libs (service kept)  2. stage + build the service
#   3. bundle with that service, pin it                  4. stage + vendorimage, check image == bundle
# Usage: build-vendor.sh --base <bundle> --out <bundle> --release <name> --note <text>   (paths workspace-relative)
# Run rebuild-native.sh first when anything under driver-source/ changed. Log: /tmp/vendorimage-build.log
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
WS=${WAYDROID_A17_WS:-$(dirname "$REPO")}
LUNCH=lineage_nvidia_waydroid_x86_64-cp2a-userdebug
OUT=$WS/src/out/target/product/waydroid_nvidia_x86_64
SVC=vendor/odm/bin/hw/android.hardware.media.c2@1.2-service-nvprolapse
args=("$@")
bundle_out=
while [ $# -gt 0 ]; do [ "$1" = --out ] && bundle_out=$2; shift; done
[ -n "$bundle_out" ] || { echo "build-vendor: --out is required" >&2; exit 2; }

python3 "$HERE/make-bundle.py" "${args[@]}"
"$WS/scripts/stage-product.sh"
"$WS/scripts/build.sh" "$LUNCH" android.hardware.media.c2@1.2-service-nvprolapse > /tmp/c2svc-build.log 2>&1 \
    || { grep -E 'error:|FAILED' /tmp/c2svc-build.log | head -20; exit 1; }
python3 "$HERE/make-bundle.py" "${args[@]}" --service "${OUT#"$WS"/}/$SVC"
"$WS/scripts/stage-product.sh"
"$WS/scripts/build.sh" "$LUNCH" vendorimage > /tmp/vendorimage-build.log 2>&1 \
    || { grep -E 'error:|FAILED' /tmp/vendorimage-build.log | head -20; exit 1; }

B=$WS/$bundle_out/payload
cmp "$OUT/$SVC" "$B/odm/bin/hw/android.hardware.media.c2@1.2-service-nvprolapse"
for l in lib64 lib; do
    cmp "$OUT/vendor/$l/libnv_bionic_native.so" "$B/vendor_extra/$l/libnv_bionic_native.so"
    cmp "$OUT/vendor/$l/egl/libEGL_nvrm.so" "$B/vendor/$l/egl/libEGL_nvrm.so"
done
echo "build-vendor: $OUT/vendor.img matches $bundle_out"
