#!/usr/bin/env bash
# Package the built nvidia vendor image, install waydroid-nvidia from the local sources with the pinned native
# bundle and that vendor (scripts/install-waydroid-nvidia.sh), then run the setup (gate + install).
# Needs sudo; SUDO_ASKPASS is used when set.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAG=v0.2.0-rc10-a17
IMG=$ROOT/src/out/target/product/waydroid_nvidia_x86_64/vendor.img
NB=$ROOT/nvidia/release/native
PIN=$ROOT/nvidia/product/vendor/nvidia-prolapse/native-bundle.json
if [ -f "$PIN" ]; then
    NB=$ROOT/$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["path"])' "$PIN")
fi
SUDO=(sudo ${SUDO_ASKPASS:+-A})

rm -rf "$ROOT/out-ota"
mkdir -p "$ROOT/out-ota"
python3 "$ROOT/nvidia/waydroid-nvidia/packaging/vendor-ota.py" "$IMG" "$NB/BUILD-RECORD.json" \
    "$ROOT/out-ota" --tag "$TAG"
"${SUDO[@]}" bash "$ROOT/scripts/install-waydroid-nvidia.sh" --no-deps
"${SUDO[@]}" env LC_ALL=C waydroid-nvidia-setup
