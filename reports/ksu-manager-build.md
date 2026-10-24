# KernelSU 本地 Manager 构建

## 产物与身份

- APK：`ksu/out/KernelSU_v3.3.1-28-gb42ad459_32708-local.apk`
- 包名：`me.weishu.kernelsu`；versionName：`v3.3.1-28-gb42ad459`；versionCode：**32708**。
- APK SHA-256：`0126daa41a4e2ac33410c9023bb835666845897b33a6b6035880d81c67239d13`。
- 内核重编译参数（也见 `ksu/out/expected.txt`）：

```text
KSU_EXPECTED_SIZE=0x02ec
KSU_EXPECTED_HASH=d77ee93d9af4c1dbf8b89cf50fd9953db3a61b9142e009a9effeeedb5693eb4f
```

签名证书为 `CN=KernelSU Local Release`，RSA 2048 位，有效期 10000 天。密钥位于 `ksu/keystore/ksu-local.jks`，密码和 alias 位于 `ksu/keystore/README`，两个文件权限均实测为 **600**，目录为 700。请保留密钥和密码用于后续同签名升级，不要提交到 Git 或公开。

## 源码和工具链

从 yay 缓存克隆到 `ksu/KernelSU`，本地分支 `local-manager` 固定在 `b42ad459`。克隆非 shallow，完整历史包含 2708 个提交；执行 `git repack -a -d` 并移除继承的 objects alternates，使容器可独立读取全部历史。原 yay 缓存未修改。

已阅读 `AGENTS.md`、`justfile`、manager Gradle 配置，以及 `.github/workflows/build-manager.yml`、`ksud.yml` 和 Rust 环境脚本。采用 CI 的构建方式：

|组件|实际版本/配置|
|---|---|
|容器|rootless Podman，`localhost/ksu-manager-build`；基于已有 Ubuntu 22.04 构建镜像|
|JDK|OpenJDK 21.0.12.1（CI 要求 Java 21）|
|Gradle / AGP / Kotlin|9.7.1 / 9.4.1 / 2.4.20|
|Android SDK|Platform 37.0 r02；compile/target SDK 37；min SDK 31|
|SDK Build Tools / CMake|37.0.0 / 3.22.1|
|Android NDK|r29，29.0.14206865，Clang 21.0.0|
|Rust / Cargo|1.99.1 / 1.99.1，stable|
|ksud target/API|`x86_64-linux-android` / 26|

该提交的 CI 不使用 cargo-ndk：通过 `.github/scripts/setup-rust-build.sh` 设置 NDK clang/linker，然后直接 `cargo build`。Cargo 依照上游未加 `--locked` 的命令更新工作副本 lockfile。Manager 通过独立 `x86_64.init.gradle` 限定 ABI，不改版本生成逻辑或 manager 源码；仅包含 x86_64。Gradle 自动安装 Platform-Tools 37.0.1。宿主机未安装工具链，未操作宿主内核模块、DKMS 或 Waydroid。

## 命令

在项目根目录运行：

```bash
podman build -t localhost/ksu-manager-build -f ksu/Containerfile ksu
podman run --rm -v "$PWD/ksu:/work" localhost/ksu-manager-build bash /work/generate-key.sh
podman run --rm --name ksu-manager-compile \
  -v "$PWD/ksu:/work" -v ksu-gradle-cache:/root/.gradle \
  -v ksu-cargo-cache:/root/.cargo/registry -v ksu-cargo-git:/root/.cargo/git \
  localhost/ksu-manager-build bash /work/build-manager.sh
podman run --rm -v "$PWD/ksu:/work" localhost/ksu-manager-build bash /work/sign-manager.sh
python ksu/apk_certificate.py \
  ksu/out/KernelSU_v3.3.1-28-gb42ad459_32708-local.apk \
  ref/kernelsu/KernelSU_v3.3.1_32680-release.apk
```

`generate-key.sh` 仅用于首次创建，已有密钥不会覆盖。构建命令先生成 ksud、复制为 `jniLibs/x86_64/libksud.so`，再执行 `assembleRelease`；签名命令完成 zipalign 后以本地 release key 签名。

## 验证

- Gradle release 构建成功；`apksigner verify --verbose --print-certs` 验证成功，**v2=true**、单一 signer。仅启用 v2，符合内核仅接受 v2 和 verity padding 签名块的限制。
- `aapt2 dump badging` 实测 versionCode **32708**、versionName 如上、native-code **x86_64**。版本公式为 `30000 + git rev-list --count HEAD = 30000 + 2708`，与内核的 32708 一致；尚未进行 Android 安装/界面验证。
- APK 包含 `lib/x86_64/libksud.so`、`libkernelsu.so` 和 `libadbroot.so`。libksud 为 x86_64 ELF，大小 3987096 字节，与 AGP strip 后的构建产物逐字节一致；SHA-256 为 `9a55b44ea8f00e84a0cfe94ec5589c55bab883170a3d72203cf0f64dbda768db`。
- `ksu/apk_certificate.py` 复现 `kernel/manager/apk_sign.c` 的 EOCD、签名块长度/ID 检查，以及 v2 首 signer → signed data → certificates → 首张 DER 证书的长度和 SHA-256；本地 APK 得到上列参数。
- 同一解析器对官方 `KernelSU_v3.3.1_32680-release.apk` 得到 **0x033b** 和 **c371061b19d8c7d7d6133c6a9bafe198fa944e50c1b31c9d8daa8d7f1fc2d2d6**，与预期完全一致。
