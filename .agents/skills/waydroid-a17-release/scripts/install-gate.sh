#!/usr/bin/env bash
# Install the locally built package exactly as a user would get it and run the release gate:
# stop the session, delete every debug file from the vendor overlay (overlay libraries win over the image),
# pacman -U, waydroid-nvidia-setup (gate + vendor install). Prints the gate summary; log /tmp/wd-setup.log.
# Usage: install-gate.sh <pkgver, e.g. 20261025.2>      (sudo; SUDO_ASKPASS honoured)
set -euo pipefail
VER=${1:?usage: install-gate.sh <pkgver>}
REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
PKG=$REPO/aur/waydroid-a17-nvidia-bin/waydroid-a17-nvidia-bin-$VER-1-x86_64.pkg.tar.zst
[ -f "$PKG" ] || { echo "install-gate: $PKG not built (package.sh)" >&2; exit 1; }
SUDO=(sudo ${SUDO_ASKPASS:+-A})
waydroid session stop >/dev/null 2>&1 || true
"${SUDO[@]}" find /var/lib/waydroid/overlay/vendor -type f -print -delete
"${SUDO[@]}" pacman -U --noconfirm "$PKG" | tail -1
rc=0
"${SUDO[@]}" env LC_ALL=C waydroid-nvidia-setup > /tmp/wd-setup.log 2>&1 || rc=$?
grep -cE '^PASS' /tmp/wd-setup.log | sed 's/^/gate cases passed: /'
grep -E 'FAIL|Release gate|byte-identical|Installed the|rror' /tmp/wd-setup.log || true
exit $rc
