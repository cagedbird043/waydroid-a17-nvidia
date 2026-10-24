#!/usr/bin/env bash
# Install committed A17 sources with the native bundle pinned by the product layer and the locally packaged A17 vendor.
# Usage: sudo bash scripts/install-waydroid-nvidia.sh [--no-deps]
# Stage only: bash scripts/install-waydroid-nvidia.sh --destdir /tmp/waydroid-a17-stage
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE=$ROOT/nvidia/waydroid-nvidia
PIN=$ROOT/nvidia/product/vendor/nvidia-prolapse/native-bundle.json
[ "$(git -c safe.directory="$SOURCE" -C "$SOURCE" branch --show-current)" = a17-local ] || {
    echo 'install-waydroid-nvidia: checkout must be on a17-local' >&2
    exit 1
}
read -r NATIVE RECORD < <(python3 -I -c 'import json,sys; p=json.load(open(sys.argv[1])); print(p["path"], p["build_record_sha256"])' "$PIN")
NATIVE=$ROOT/$NATIVE
[ "$(sha256sum "$NATIVE/BUILD-RECORD.json" | cut -d' ' -f1)" = "$RECORD" ] || {
    echo "install-waydroid-nvidia: $NATIVE/BUILD-RECORD.json does not match the pin $PIN" >&2
    exit 1
}
exec bash "$SOURCE/packaging/install.sh" --tag v0.2.0-rc10 \
    --from "$ROOT/nvidia/release" --source "$SOURCE" --native "$NATIVE" --vendor "$ROOT/out-ota" "$@"
