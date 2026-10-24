#!/usr/bin/env bash
# Put the ported nvidia-a17 commits (nvidia/work clones) on top of the tree's projects, after apply-waydroid-patches,
# and stage the product layer. Each port lists the upstream commit it was made on; only the commits after it are
# cherry-picked, so ATV's own Waydroid patches already applied to a project stay underneath.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# tree path -> clone dir and the upstream commit the port starts from
PORTS=(
    "hardware/waydroid           hardware_waydroid   3af187c"
    "external/minigbm            minigbm             5f5797c"
    "hardware/interfaces         hardware_interfaces 1b0bcde"
    "external/wayland-protocols  wayland-protocols   2dabfe6"
)
for entry in "${PORTS[@]}"; do
    read -r path clone base <<<"$entry"
    proj=$ROOT/src/$path
    if git -C "$proj" rev-parse -q --verify nvidia-a17 >/dev/null; then
        echo "$path: nvidia-a17 already present, skipping"
        continue
    fi
    git -C "$proj" fetch -q "$ROOT/nvidia/work/$clone" nvidia-a17
    git -C "$proj" checkout -q -b nvidia-a17
    git -C "$proj" -c user.name=local -c user.email=local@localhost cherry-pick -x "$base"..FETCH_HEAD >/dev/null
    echo "$path: $(git -C "$proj" rev-list --count "$base"..FETCH_HEAD) port commits on $(git -C "$proj" rev-parse --short HEAD~"$(git -C "$proj" rev-list --count "$base"..FETCH_HEAD)")"
done
"$ROOT/scripts/stage-product.sh"
