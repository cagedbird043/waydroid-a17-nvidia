#!/usr/bin/env bash
set -euo pipefail
umask 077
source /work/keystore/README
export KEYSTORE_PASSWORD KEY_PASSWORD
keytool -genkeypair -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 -storepass:env KEYSTORE_PASSWORD -keypass:env KEY_PASSWORD -dname 'CN=KernelSU Local Release' -storetype JKS -keystore "$KEYSTORE_FILE"
chmod 600 "$KEYSTORE_FILE"
