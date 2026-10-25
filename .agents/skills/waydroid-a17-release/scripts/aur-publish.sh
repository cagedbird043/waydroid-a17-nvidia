#!/usr/bin/env bash
# After the GitHub release is up: recompute the AUR checksums from the published URLs (local copies removed,
# so makepkg really downloads), rebuild once from them, regenerate .SRCINFO, commit that to this repository
# and push PKGBUILD/.SRCINFO/.install to the AUR. Pushes to origin and the AUR: run only when told to release.
# Usage: aur-publish.sh <tag>
set -euo pipefail
TAG=${1:?usage: aur-publish.sh <tag>}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
A=$REPO/aur/waydroid-a17-nvidia-bin
grep -qx "_tag=$TAG" "$A/PKGBUILD" || { echo "aur-publish: PKGBUILD is not at $TAG" >&2; exit 1; }
gh release view "$TAG" >/dev/null
cd "$A"
rm -rf src pkg "waydroid-a17-nvidia-$TAG.tar.gz" vendor-"$TAG".img.zst.part* \
    "waydroid-a17-nvidia-native-x86_64-$TAG.tar.zst" ./*.pkg.tar.zst
# GitHub release downloads drop now and then (TLS EOF); files already fetched are kept between attempts
ok=
for _ in 1 2 3 4 5; do updpkgsums && { ok=1; break; }; sleep 15; done
[ -n "$ok" ] || { echo "aur-publish: downloads kept failing" >&2; exit 1; }
makepkg -fC > /tmp/wd-makepkg.log 2>&1 || { tail -20 /tmp/wd-makepkg.log; exit 1; }
makepkg --printsrcinfo > .SRCINFO
rm -rf src pkg
cd "$REPO"
git add aur/waydroid-a17-nvidia-bin/PKGBUILD aur/waydroid-a17-nvidia-bin/.SRCINFO
git diff --cached --quiet || git commit -qm "AUR：$TAG 的校验和与 .SRCINFO"
git push -q origin HEAD
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
git clone -q ssh://aur@aur.archlinux.org/waydroid-a17-nvidia-bin.git "$T/aur"
cp "$A/PKGBUILD" "$A/.SRCINFO" "$A/waydroid-a17-nvidia.install" "$T/aur/"
cd "$T/aur"
git add -A
git diff --cached --quiet && { echo "aur-publish: AUR already at $TAG"; exit 0; }
git commit -qm "更新到 $TAG"
git push -q origin master
git log --oneline -1
