# KernelSU（LKM，宿主机 DKMS）

Waydroid 共用宿主机内核，所以 KernelSU 以内核模块形式装在宿主机上。维护源码基于 supechicken 的 `waydroid-experimental` 分支，容器启动时 Android 的 init 运行 `/data/adb/ksud`。

内核模块只认一个管理器签名。预签 Manager 与对应 DKMS 包使用维护者的公开证书；自己签名时，必须将
`kernelsu-dkms/PKGBUILD` 的 `_ksu_expected_size` / `_ksu_expected_hash` 换成自己的证书长度和 SHA-256。
管理器、ksud 与模块的版本计数也必须一致。

以下命令从工作区根目录（`publish/` 的上一级）运行，需要 podman、现有 `localhost/ksu-manager-build` 编译镜像，以及同维护版的完整源码 bundle。构建镜像定义见 `publish/kernelsu/manager/Containerfile`。

## 1. 管理器源码

```bash
mkdir -p ksu
cp publish/kernelsu/manager/* ksu/
# 将维护版的 KernelSU-4e752f94.bundle 放到 ksu/out/ 后：
git clone ksu/out/KernelSU-4e752f94.bundle ksu/KernelSU
git -C ksu/KernelSU checkout 4e752f941797dfe203788d618e026abf5a1088b5
```

管理器、ksud 和模块的 versionCode 都是 `30000 + git rev-list --count HEAD`。三者必须来自同一完整（非 shallow）源码提交；`sign-manager.sh` 会核对待签 APK 的 versionCode 与当前源码计数，不一致时拒绝签名。

维护版 `v3.3.1-33-g4e752f94`（计数 `2713`，versionCode `32713`）保留 b42ad459 的七个容器/LKM 适配，仅移植官方 Manager shell 参数转义、ksud profile/template 路径验证、wrapped file 重开引用平衡三个修复，并补充路径边界测试及修正锁文件中三处悬空 bitflags 版本引用；不升级整个上游分支。

维护版的 Manager APK、DKMS 包和完整源码 `KernelSU-4e752f94.bundle` 随
[`a17-20261111-1`](https://github.com/cagedbird043/waydroid-a17-nvidia/releases/tag/a17-20261111-1) 提供。
源码 bundle SHA-256：`012f19894b81ae606f17bcec0673e16ce3d810bdf1c881abc888cfdd8c81632a`。

## 2. 生成你自己的签名密钥

```bash
mkdir -p ksu/keystore && chmod 700 ksu/keystore
cat > ksu/keystore/README <<'EOF'
KEYSTORE_FILE=/work/keystore/ksu-local.jks
KEY_ALIAS=ksu-local
KEYSTORE_PASSWORD=<自己定>
KEY_PASSWORD=<自己定>
EOF
chmod 600 ksu/keystore/README
podman build -t localhost/ksu-manager-build -f ksu/Containerfile ksu
podman run --rm -v "$PWD/ksu:/work" localhost/ksu-manager-build bash /work/generate-key.sh
```

`ksu/keystore/` 就是你的 root 管理器私钥，不要提交、不要公开。

## 3. 编译并签名管理器

```bash
podman run --rm --cpus=4 -v "$PWD/ksu/KernelSU:/work/KernelSU" \
  -v "$PWD/ksu/build-manager.sh:/work/build-manager.sh:ro" \
  -v "$PWD/ksu/x86_64.init.gradle:/work/x86_64.init.gradle:ro" \
  -v ksu-gradle-cache:/root/.gradle -v ksu-cargo-cache:/root/.cargo/registry \
  -v ksu-cargo-git:/root/.cargo/git \
  localhost/ksu-manager-build bash /work/build-manager.sh
podman run --rm -v "$PWD/ksu:/work" localhost/ksu-manager-build bash /work/sign-manager.sh
APK=ksu/out/KernelSU_v3.3.1-33-g4e752f94_32713-local.apk
python3 ksu/apk_certificate.py "$APK"
```


路径验证使用独立于 Android 的共享模块，宿主单测必须运行 `cargo test --locked --jobs 4 --manifest-path userspace/ksud/Cargo.toml profile_path::tests` 并看到两个测试执行。`profile` 模块仅在 Android 编译，宿主用 `profile::tests` 过滤会得到零测试，不能作为验证。容器继续使用上述三个 KSU 专用缓存和 `--cpus=4`；Manager 单测命令为 `./gradlew --no-daemon --max-workers=4 -I /work/x86_64.init.gradle :app:testDebugUnitTest`，本树未注册 release 单测任务。构建挂载不含私钥目录。
最后一条打印 `KSU_EXPECTED_SIZE` 和 `KSU_EXPECTED_HASH`。签名只用 v2（内核不接受 v3 等其他签名块）。

## 4. 编译安装内核模块

```bash
# PKGBUILD 从同版 Release 获取完整、固定 SHA-256 的源码 bundle。
# 已下载到 ksu/out/ 时复用该缓存，不修改 yay 缓存：
(cd publish/kernelsu/kernelsu-dkms && \
  SRCDEST="$(realpath ../../../ksu/out)" makepkg --cleanbuild --noconfirm)
# 安装须由部署者单独执行；可能触发 DKMS 编译，先确认当前内核头文件齐全。
sudo pacman -U publish/kernelsu/kernelsu-dkms/kernelsu-dkms-3.3.1+33+g4e752f94-1-any.pkg.tar.zst
sudo install -m 644 publish/host/kernelsu-load.service /etc/systemd/system/
sudo systemctl enable --now kernelsu-load.service
```

`kernelsu-load.service` 在 `waydroid-container` 之前加载模块。

## 5. 装进 Android

`ksud` 已经在管理器 APK 里（`lib/x86_64/libksud.so`）：

```bash
APK=ksu/out/KernelSU_v3.3.1-33-g4e752f94_32713-local.apk
unzip -p "$APK" lib/x86_64/libksud.so > /tmp/ksud &&
  sudo install -D -m 755 -o root -g root /tmp/ksud ~/.local/share/waydroid/data/adb/ksud
# 须先启动桌面用户的 Waydroid session，并等待 Android ready；仅启动容器服务不够。
publish/.agents/skills/waydroid-a17-test/scripts/session-restart.sh
SUDO_ASKPASS=/usr/bin/ksshaskpass \
  publish/.agents/skills/waydroid-a17-test/scripts/guest.sh '/data/adb/ksud install'
waydroid app install "$APK"
waydroid app launch me.weishu.kernelsu
```

管理器首页应显示 Working（LKM）。清空 Waydroid 的 data 后要重做第 5 步。

## 部署边界

Manager/ksud 可重新构建；签名只由部署者运行现有签名脚本，沿用原密钥。构建不需要挂载 `keystore/`，不要读取或记录其内容。已记录的公开证书长度为 `0x02ec`，SHA-256 为 `d77ee93d9af4c1dbf8b89cf50fd9953db3a61b9142e009a9effeeedb5693eb4f`。

安装 DKMS 包不等于正在运行的模块已更新。包装文件引用修复只有新模块实际加载后生效；不要强制卸载正在提供 root 的模块。部署前须确认 Waydroid 已停止、没有模块使用者、模块能正常卸载且新模块已为当前内核成功编译；若不能安全卸载，就保留旧模块运行并将内核修复标为待激活，不重启宿主、不影响 RustDesk。更新前保护 `/data` 和原密钥，不清除 Android 数据。
