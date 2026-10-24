# KernelSU（LKM，宿主机 DKMS）

Waydroid 共用宿主机内核，所以 KernelSU 以内核模块形式装在宿主机上（AUR `kernelsu-dkms`，supechicken 的 `waydroid-experimental` 分支），容器启动时 Android 的 init 运行 `/data/adb/ksud`。

内核模块只认一个管理器签名。官方 KernelSU 管理器的 versionCode 与这个分支的模块对不上，所以这里自己编译管理器、用自己的密钥签名，再把该证书的长度和 SHA-256 编进模块。`kernelsu-dkms/PKGBUILD` 里的 `_ksu_expected_size` / `_ksu_expected_hash` 是维护者自己的密钥，**你必须换成自己的**，否则你签的管理器不会被认。

以下命令都在本仓库根目录运行，需要 podman，以及本仓库 `container/` 的编译镜像（`localhost/waydroid-a17-build`，见根目录 README）。

## 1. 管理器源码

```bash
mkdir -p ksu
cp kernelsu/manager/* ksu/
git clone -b waydroid-experimental https://github.com/supechicken/KernelSU ksu/KernelSU
git -C ksu/KernelSU checkout b42ad45981ede55fa84ccdf102956349812e31a5
```

管理器的 versionCode 是 `30000 + git rev-list --count HEAD`（这个提交为 32708），必须与模块编译时的版本一致。换别的提交时，同时改 `sign-manager.sh` 里的 `2708` / `32708`，并让 `kernelsu-dkms` 编同一个提交。

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
podman run --rm -v "$PWD/ksu:/work" -v ksu-gradle-cache:/root/.gradle \
  -v ksu-cargo-cache:/root/.cargo/registry -v ksu-cargo-git:/root/.cargo/git \
  localhost/ksu-manager-build bash /work/build-manager.sh
podman run --rm -v "$PWD/ksu:/work" localhost/ksu-manager-build bash /work/sign-manager.sh
python3 ksu/apk_certificate.py ksu/out/KernelSU_*_32708-local.apk
```

最后一条打印 `KSU_EXPECTED_SIZE` 和 `KSU_EXPECTED_HASH`。签名只用 v2（内核不接受 v3 等其他签名块）。

## 4. 编译安装内核模块

```bash
yay -G kernelsu-dkms            # 取 AUR 包的其余文件（Makefile、dkms.conf、补丁等）
cp kernelsu/kernelsu-dkms/PKGBUILD kernelsu-dkms/
# 把 PKGBUILD 里的 _ksu_expected_size / _ksu_expected_hash 改成第 3 步打印的值
(cd kernelsu-dkms && makepkg -si)
sudo install -m 644 host/kernelsu-load.service /etc/systemd/system/
sudo systemctl enable --now kernelsu-load.service
```

`kernelsu-load.service` 在 `waydroid-container` 之前加载模块。

## 5. 装进 Android

`ksud` 已经在管理器 APK 里（`lib/x86_64/libksud.so`）：

```bash
unzip -p ksu/out/KernelSU_*_32708-local.apk lib/x86_64/libksud.so > /tmp/ksud
sudo install -D -m 755 -o root -g root /tmp/ksud ~/.local/share/waydroid/data/adb/ksud
sudo waydroid shell -- /data/adb/ksud install
waydroid app install ksu/out/KernelSU_*_32708-local.apk
waydroid session stop   # 再启动会话
```

管理器首页应显示 Working（LKM）。清空 Waydroid 的 data 后要重做第 5 步。
