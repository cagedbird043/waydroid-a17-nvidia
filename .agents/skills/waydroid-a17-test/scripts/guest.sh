#!/usr/bin/env bash
# Run a shell command as root inside the running Waydroid container.
# Usage: guest.sh '<command>'      (sudo; set SUDO_ASKPASS for non-interactive use)
set -euo pipefail
exec sudo ${SUDO_ASKPASS:+-A} lxc-attach -P /var/lib/waydroid/lxc -n waydroid --clear-env \
    -v PATH=/system/bin:/vendor/bin -- /system/bin/sh -c "$1"
