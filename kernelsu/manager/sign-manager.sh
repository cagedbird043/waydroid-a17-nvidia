#!/usr/bin/env bash
set -euo pipefail
git config --global --add safe.directory /work/KernelSU
mkdir -p /work/out
shopt -s nullglob
apks=(/work/KernelSU/manager/app/build/outputs/apk/release/*.apk)
[[ ${#apks[@]} == 1 ]]
version=$(git -C /work/KernelSU describe --tags --always)
count=$(git -C /work/KernelSU rev-list --count HEAD)
[[ $(git -C /work/KernelSU rev-parse --is-shallow-repository) == false ]]
version_code=$((30000 + count))
badging=$(aapt2 dump badging "${apks[0]}")
[[ $badging =~ versionCode=\'([0-9]+)\' ]]
[[ ${BASH_REMATCH[1]} == "$version_code" ]] || {
    echo "APK versionCode does not match source commit count; rebuild before signing" >&2
    exit 1
}
[[ $badging == *"versionName='$version'"* ]] || {
    echo "APK versionName does not match source revision; rebuild before signing" >&2
    exit 1
}
source /work/keystore/README
export KEYSTORE_PASSWORD KEY_PASSWORD
output="/work/out/KernelSU_${version}_${version_code}-local.apk"
zipalign -f -p 4 "${apks[0]}" /work/out/aligned.apk
# KernelSU rejects other signing-block IDs, including v3: sign with v2 only.
apksigner sign --ks "$KEYSTORE_FILE" --ks-key-alias "$KEY_ALIAS" --ks-pass env:KEYSTORE_PASSWORD --key-pass env:KEY_PASSWORD --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled false --v4-signing-enabled false --out "$output" /work/out/aligned.apk
rm /work/out/aligned.apk
apksigner verify --verbose --print-certs "$output"
aapt2 dump badging "$output"
java -version
rustc --version
cargo --version
