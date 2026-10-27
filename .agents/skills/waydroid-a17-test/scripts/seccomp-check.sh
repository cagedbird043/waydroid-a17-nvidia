#!/usr/bin/env bash
# Cold init pre-exec + steady codec tracing. Optional policy is a temporary RO bind.
# Usage: seccomp-check.sh OUTPUT [POLICY] [steady command [args...]]
set +e
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[[ $# -ge 1 ]] || { echo "usage: $0 OUTPUT [POLICY] [steady command...]" >&2; exit 2; }
OUT=$1; shift
POLICY=${1:-}; [[ $# == 0 ]] || shift
mkdir -p "$OUT" || exit 1
OUT=$(realpath "$OUT")
if [[ ${WD_GUEST_LOCKED:-0} != 1 ]]; then
    exec flock /tmp/wd-guest.lock env WD_GUEST_LOCKED=1 "$0" "$OUT" "$POLICY" "$@"
fi
# lxc-attach changes ownership/mode of regular stdout/stderr descriptors.
# Always give it a pipe, including commands inside cleanup redirections.
guest() {
    "$HERE/guest.sh" "$@" 2>&1 | cat
    return "${PIPESTATUS[0]}"
}
G=guest
S=android-hardware-media-c2-nvprolapse
B=android.hardware.media.c2@1.2-service-nvprolapse
P=/vendor/odm/etc/seccomp_policy/android.hardware.media.c2@1.2-nvprolapse.policy
D=/data/local/tmp/c2-seccomp-$$
SUDO=(sudo ${SUDO_ASKPASS:+-A})
bound=0
tracer_job=
# All waits are bounded, including init stop/start and tracer attach/detach.
wait_guest() {
    local condition=$1
    "$G" "set +e; for i in \$(seq 1 100); do $condition && exit 0; sleep .1; done; exit 1"
}
stop_service() {
    "$G" "setprop ctl.sigstop_off '$S'; stop '$S'" || return 1
    wait_guest "[ \"\$(getprop init.svc.$S)\" = stopped ]"
}
detach() {
    "$G" "p=\$(getprop init.svc_debug_pid.$S); if [ -r /proc/\$p/status ]; then t=\$(awk '/TracerPid/ {print \$2}' /proc/\$p/status); [ \"\$t\" = 0 ] || kill -INT \"\$t\"; fi" || return 1
    if [[ -n $tracer_job ]]; then wait "$tracer_job"; tracer_job=; fi
    return 0
}
cleanup() {
    status=$?
    trap - EXIT
    detach >>"$OUT/restore.log" 2>&1
    stop_service >>"$OUT/restore.log" 2>&1 || status=1
    if [[ $bound == 1 ]]; then "$G" "umount '$P'" >>"$OUT/restore.log" 2>&1 || status=1; fi
    "$G" "start '$S'; sha256sum '$P'; rm -rf '$D'" >>"$OUT/restore.log" 2>&1 || status=1
    wait_guest "[ \"\$(getprop init.svc.$S)\" = running ]" >>"$OUT/restore.log" 2>&1 || status=1
    "$G" "sha256sum '$P'; p=\$(pidof '$B'); cat /proc/\$p/status" >"$OUT/restored-health.log" 2>&1 || status=1
    "$G" "p=\$(pidof '$B'); grep -q '^TracerPid:[[:space:]]*0$' /proc/\$p/status && grep -q '^Seccomp:[[:space:]]*2$' /proc/\$p/status" >>"$OUT/restored-health.log" 2>&1 || status=1
    actual=$("$G" "sha256sum '$P'" | cut -d' ' -f1)
    [[ $actual == "$original" ]] || status=1
    printf '%s\n' "$status" >"$OUT/exit-code"
    exit "$status"
}
original=$("$G" "sha256sum '$P'" | cut -d' ' -f1) || exit 1
[[ $original =~ ^[0-9a-f]{64}$ ]] || exit 1
printf '%s\n' "$original" >"$OUT/original.sha256"
trap cleanup EXIT
"$G" "mkdir -p '$D'; chmod 755 '$D'" || exit 1
if [[ -n $POLICY ]]; then
    "${SUDO[@]}" cp "$POLICY" "$HOME/.local/share/waydroid/data${D#/data}/policy" || exit 1
    "$G" "chmod 644 '$D/policy'" || exit 1
    stop_service || exit 1
    "$G" "mount -o bind '$D/policy' '$P'" || exit 1
    bound=1
    pid=$("${SUDO[@]}" lxc-info -P /var/lib/waydroid/lxc -n waydroid -pH) || exit 1
    "${SUDO[@]}" python3 - "$pid" "$P" <<'PY'
import ctypes, os, sys
lib = ctypes.CDLL(None, use_errno=True)
ns = os.open('/proc/' + sys.argv[1] + '/ns/mnt', os.O_RDONLY)
root = os.open('/proc/' + sys.argv[1] + '/root', os.O_RDONLY | os.O_DIRECTORY)
os.setns(ns, 0)
os.fchdir(root)
os.chroot('.')
if lib.mount(None, sys.argv[2].encode(), None, 4096 | 32 | 1, None):
    raise OSError(ctypes.get_errno(), 'read-only bind remount')
PY
    [[ $? == 0 ]] || exit 1
    wanted=$(sha256sum "$POLICY" | cut -d' ' -f1)
    "$G" "sha256sum '$P'; cat /proc/self/mountinfo" >"$OUT/deployed.log" || exit 1
    actual=$("$G" "sha256sum '$P'" | cut -d' ' -f1)
    [[ $wanted == "$actual" ]] || exit 1
fi
# Expand the ACTUAL mounted policy recursively; include cycles fail closed.
expand_policy() {
    local path=$1 ancestry=${2:-}
    [[ " $ancestry " != *" $path "* ]] || return 1
    local text line
    text=$("$G" "cat '$path'") || return 1
    while IFS= read -r line; do
        if [[ $line =~ ^@include[[:space:]]+([^[:space:]]+) ]]; then
            expand_policy "${BASH_REMATCH[1]}" "$ancestry $path" || return 1
        else printf '%s\n' "$line"; fi
    done <<<"$text"
}
expand_policy "$P" >"$OUT/policy.expanded" || exit 1
stop_service || exit 1
"$G" "setprop ctl.sigstop_on '$S'; start '$S'" || exit 1
wait_guest "p=\$(getprop init.svc_debug_pid.$S); [ -n \"\$p\" ] && grep -q '^State:.*T' /proc/\$p/status" || exit 1
"$G" "p=\$(getprop init.svc_debug_pid.$S); cat /proc/\$p/status" >"$OUT/preexec.log" || exit 1
attach() {
    local window=$1
    target_pid=$("$G" "getprop init.svc_debug_pid.$S") || return 1
    "$G" "p=\$(getprop init.svc_debug_pid.$S); exec timeout -s INT -k 5 180 strace -f -qq -I 1 -s 4096 -o '$D/$window.strace' -p \"\$p\"" >"$OUT/$window-tracer.log" 2>&1 &
    tracer_job=$!
    wait_guest "p=\$(getprop init.svc_debug_pid.$S); t=\$(awk '/TracerPid/ {print \$2}' /proc/\$p/status); [ -n \"\$t\" ] && [ \"\$t\" != 0 ]"
}
assert_attached() {
    "$G" "p=\$(getprop init.svc_debug_pid.$S); [ \"\$p\" = '$target_pid' ] && t=\$(awk '/TracerPid/ {print \$2}' /proc/\$p/status) && [ -n \"\$t\" ] && [ \"\$t\" != 0 ]"
}
attach cold || exit 1
"$G" "setprop ctl.sigstop_off '$S'; p=\$(getprop init.svc_debug_pid.$S); kill -CONT \"\$p\"" || exit 1
# lshal verifies that the service reached Store registration, not merely running.
"$G" 'for i in $(seq 1 20); do timeout -s KILL 2 lshal debug android.hardware.media.c2@1.2::IComponentStore/default && exit 0; sleep .1; done; exit 1' >"$OUT/store-debug.log" 2>&1 || exit 1
sleep 1
assert_attached || exit 1
cold_pid=$target_pid
detach || exit 1
attach steady || exit 1
[[ $target_pid == "$cold_pid" ]] || exit 1
if [[ $# -gt 0 ]]; then
    "$@" 2>&1 | cat >"$OUT/clients.log"
    client_rc=${PIPESTATUS[0]}
else
    "$HERE/codec-smoke.sh" 2>&1 | cat >"$OUT/clients.log"
    client_rc=${PIPESTATUS[0]}
fi
printf '%s\n' "$client_rc" >"$OUT/client-exit-code"
assert_attached || exit 1
detach || exit 1
for window in cold steady; do
    "$G" "chmod 644 '$D/$window.strace'; cat '$D/$window.strace'" >"$OUT/$window.strace" || exit 1
done
python3 "$HERE/seccomp-report.py" "$OUT" >"$OUT/comparison.log" 2>&1
report_rc=$?
[[ $client_rc == 0 && $report_rc == 0 ]] || exit 1
exit 0
