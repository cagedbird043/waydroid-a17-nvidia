#!/usr/bin/env bash
# Build the release assets and a local AUR package from them, without downloading anything we publish.
#   vendor.img -> vendor.img.zst (zstd -19) -> 50 MiB parts + vendor.img.zst.sha256 (parts, archive, image)
#   pinned native bundle -> waydroid-a17-nvidia-native-x86_64.tar.zst (reproducible tar)
#   places the assets under the PKGBUILD's source names, updpkgsums, makepkg
# The release commit must exist already and carry _tag/pkgver: the repository tarball is `git archive HEAD`,
# which is what GitHub serves for the tag once it is pushed. A first run with a new tag bumps the PKGBUILD and
# stops so the bump goes into that commit.
# Usage: package.sh <tag, e.g. a17-20261025-2>
set -euo pipefail
TAG=${1:?usage: package.sh <tag>}
[[ $TAG =~ ^a17-([0-9]{8})-([0-9]+)$ ]] || { echo "package: tag must look like a17-YYYYMMDD-N" >&2; exit 2; }
PKGVER=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
WS=${WAYDROID_A17_WS:-$(dirname "$REPO")}
IMG=$WS/src/out/target/product/waydroid_nvidia_x86_64/vendor.img
NB=$WS/$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["path"])' "$WS/nvidia/product/vendor/nvidia-prolapse/native-bundle.json")
A=$REPO/aur/waydroid-a17-nvidia-bin
cd "$REPO"
if ! grep -qx "_tag=$TAG" "$A/PKGBUILD"; then
    sed -i -e "s/^pkgver=.*/pkgver=$PKGVER/" -e 's/^pkgrel=.*/pkgrel=1/' -e "s/^_tag=.*/_tag=$TAG/" "$A/PKGBUILD"
    echo "package: PKGBUILD bumped to $TAG ($PKGVER); commit it with the release changes, then run again" >&2
    exit 1
fi
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "package: commit the publish changes first" >&2; exit 1; }

rm -f vendor.img.zst vendor.img.zst.part* vendor.img.zst.sha256 waydroid-a17-nvidia-native-x86_64.tar.zst
zstd -q -19 -T0 "$IMG" -o vendor.img.zst
split -b 50M -d -a 2 vendor.img.zst vendor.img.zst.part
{ sha256sum vendor.img.zst.part*; sha256sum vendor.img.zst; sha256sum "$IMG" | sed 's|  .*|  vendor.img|'; } > vendor.img.zst.sha256
(cd "$NB" && tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 --zstd \
    -cf "$REPO/waydroid-a17-nvidia-native-x86_64.tar.zst" .)
parts=$(ls vendor.img.zst.part* | wc -l)
listed=$(grep -c 'vendor-$_tag.img.zst.part0[0-9]::' "$A/PKGBUILD")
[ "$parts" = "$listed" ] || { echo "package: $parts image parts, the PKGBUILD lists $listed; fix its source array" >&2; exit 1; }

rm -f "$A"/vendor-a17-*.img.zst.part* "$A"/waydroid-a17-nvidia-a17-*.tar.gz \
    "$A"/waydroid-a17-nvidia-native-x86_64-a17-*.tar.zst "$A"/*.pkg.tar.zst
git archive --format=tar.gz --prefix="waydroid-a17-nvidia-$TAG/" HEAD > "$A/waydroid-a17-nvidia-$TAG.tar.gz"
cp waydroid-a17-nvidia-native-x86_64.tar.zst "$A/waydroid-a17-nvidia-native-x86_64-$TAG.tar.zst"
for p in vendor.img.zst.part*; do cp "$p" "$A/vendor-$TAG.img.zst.${p##*.}"; done
# upstream rc10 assets: reuse the workspace copies when GitHub downloads fail
for f in "$WS"/nvidia/release/waydroid-nvidia-*-v0.2.0-rc10.tar.zst; do cp -n "$f" "$A/" 2>/dev/null || true; done
cd "$A"
updpkgsums
makepkg -fC > /tmp/wd-makepkg.log 2>&1 || { tail -20 /tmp/wd-makepkg.log; exit 1; }
ls -1 "$A/waydroid-a17-nvidia-bin-$PKGVER-1-x86_64.pkg.tar.zst"
cat "$REPO/vendor.img.zst.sha256"
