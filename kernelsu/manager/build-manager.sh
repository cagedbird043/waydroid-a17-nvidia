#!/usr/bin/env bash
set -euo pipefail
cd /work/KernelSU
git config --global --add safe.directory /work/KernelSU
source .github/scripts/setup-rust-build.sh x86_64-linux-android 26
cargo build --target "$TRIPLE" --release --manifest-path userspace/ksud/Cargo.toml
mkdir -p manager/app/src/main/jniLibs/x86_64
cp target/x86_64-linux-android/release/ksud manager/app/src/main/jniLibs/x86_64/libksud.so
cd manager
./gradlew --no-daemon --max-workers=6 -I /work/x86_64.init.gradle assembleRelease
