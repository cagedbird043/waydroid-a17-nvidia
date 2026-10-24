# Waydroid A17 NVIDIA

[English](#english) · [中文](#中文)

---

## English

Waydroid with Android 17 (LineageOS 24.0), hardware acceleration on NVIDIA GPUs, KernelSU root, and desktop integration for KDE Plasma. The goal is one combination that is good for daily use, not a general-purpose distribution.

> Personal project, provided as is. Tested only on the author's machine: RTX 4060 Laptop, NVIDIA open driver 615.78.08, KDE Plasma 6 on Wayland, Arch Linux with the zen kernel. Issues and PRs are welcome, but replies and support are not guaranteed.

### Components

| Part | Source |
|---|---|
| system | LineageOS 24.0 image from [WayDroid-ATV](https://github.com/WayDroid-ATV) (VANILLA or GAPPS), unmodified |
| vendor | Built here: the nvidia-prolapse mode of [waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia) ported onto the ATV lineage-24.0 device tree. See Releases |
| host | Waydroid from waydroid-nvidia with the patches in `patches/waydroid-nvidia/` |
| root | Host `kernelsu-dkms` plus a self-signed manager. See [`kernelsu/README.md`](kernelsu/README.md) |

### Features

- **NVIDIA acceleration**: ANGLE → NVK (dual graphics queues) → NVIDIA kernel driver. HWUI renders with Vulkan (skiavk). H.264, HEVC, VP9 and AV1 are decoded on NVDEC.
- **Multi-window**: after `waydroid prop set persist.waydroid.multi_windows true`, every Android app gets its own KDE window. KWin draws the title bar and handles moving, resizing and closing. `waydroid show-full-ui` opens the Android desktop in one KDE window; when it is closed, apps return to their own windows.
- **Window positions**: the optional KWin script `host/kwin-waydroid-placement` reopens each app window where it was last closed. Positions are stored in `~/.config/kwin-waydroid-placement.conf` and survive logout.
- **Host input method**: type into Android with fcitx5, ibus and other host IMEs through Wayland `text-input-v3`. The candidate window follows the cursor. On the Android side, the IME `WaydroidHostIme` ships in vendor and is enabled on first boot.
- **Clipboard**: two-way sync with the host through `ext-data-control`, independent of window focus.
- **Sound**: output through the host's PulseAudio. The Android media volume defaults to maximum, so the host controls the volume.
- **File sharing**: the host's `~/Downloads` appears in Android as `Download/Host`. Both sides read and write the same files; files created in Android belong to the host user. Files added on the host are announced to the Android media library automatically. Other folders can be configured with `shared_folders` in the `[waydroid]` section of `/var/lib/waydroid/waydroid.cfg`: one `host folder:storage path` per line, with the storage path under a standard folder such as `Download` or `Pictures`.
- **DRM**: Widevine L3 (software, no HDCP); streaming apps usually limit playback to SD.
- **Google apps**: use ATV's GAPPS system image; the vendor image is the same.

### Performance

Basemark GPU, Vulkan, 3840×2160, Medium, offscreen: the host with the NVIDIA proprietary driver scores 35657; Waydroid scores 29369, about 82% of the host. The Android build of Basemark only ships ETC2 textures, which the GPU cannot sample natively, so the real driver gap is smaller than this. 3DMark Wild Life Extreme scores about 12300–13100 (about 74 FPS). Details are in [`reports/`](reports/).

### Install (Arch Linux, AUR)

```bash
yay -S waydroid-a17-nvidia-bin
```
Basemark GPU, Vulkan, 3840×2160, Medium, offscreen: the host with the NVIDIA proprietary driver scores 35657; Waydroid scores 29369, about 82% of the host. The Android build of Basemark only ships ETC2 textures, which NVK does not support natively, while the host uses BC7, so the comparison favors the host. 3DMark Wild Life Extreme scores about 12300–13100 (about 74 FPS). Details are in [`reports/`](reports/).
The package contains the patched Waydroid host side, the vendor image from this repository's Releases with its matching native driver bundle, and the KWin script. It does not contain the Android system image or KernelSU. After installing:

```bash
sudo mkdir -p /etc/waydroid-extra/images
# ATV 20261017 system image (GAPPS or VANILLA): https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20261017
sudo bsdtar -xf lineage-24.0-20261017-GAPPS-waydroid_x86_64-system.zip -C /etc/waydroid-extra/images system.img
sudo bsdtar -xf /usr/lib/waydroid-nvidia/vendor/waydroid-nvidia-vendor-x86_64-*.zip -C /etc/waydroid-extra/images vendor.img
sudo waydroid init -f
sudo waydroid-nvidia-setup        # runs the release gate on this GPU and kernel module, then installs the vendor image
waydroid prop set persist.waydroid.multi_windows true
waydroid session start
```

Requirements: the NVIDIA open kernel modules (the author uses 615.78.08) and binder with binderfs. After an NVIDIA driver update and reboot, run `sudo waydroid-nvidia-setup` again. Enable the KWin script under System Settings → Window Management → KWin Scripts → "Waydroid card placement". For root, see [`kernelsu/`](kernelsu/).

### Manual install

On other distributions, take these from Releases:

- the vendor image, uploaded in parts:
  ```bash
  cat vendor.img.zst.part* > vendor.img.zst && zstd -d vendor.img.zst
  sha256sum -c vendor.img.zst.sha256   # checks the parts, the archive and the image
  ```
- the native driver bundle `waydroid-a17-nvidia-native-x86_64.tar.zst`, which must match the vendor image.

Then:

1. Install the waydroid-nvidia host side as described in the README of its `public-test` branch, after running `git am patches/waydroid-nvidia/*.patch` on its source. Extract the native bundle into `/usr/lib/waydroid-nvidia/native/release/`.
2. Extract `system.img` from ATV's `lineage-24.0-*-waydroid_x86_64-system.zip`.
3. Put `system.img` and `vendor.img` into Waydroid's image directory, for example `/etc/waydroid-extra/images/`, and run `waydroid-nvidia-setup`.

`aur/waydroid-a17-nvidia-bin/PKGBUILD` shows the exact file layout.

### Build from source

You need podman and plenty of disk space: about 100 GB of source plus build output. A full vendor image takes hours; with ccache, rebuilding a single library takes minutes.

1. Build the container: `podman build --build-arg ROOT="$PWD" -t localhost/waydroid-a17-build container`. `scripts/build.sh` mounts the project at the same path inside the container, because the Mesa cross build uses lld from the tree.
2. `scripts/sync.sh` syncs LineageOS 24.0 and the ATV manifest into `src/`, then runs `apply-waydroid-patches`.
3. Apply `git am patches/<repo>/*.patch` on the base of each repository below, and copy `nvidia-product/` to `src/vendor/nvidia-prolapse`.
4. `scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug vendorimage`

To test a single module, build it (for example `hwcomposer.waydroid`), copy the file from `out/.../vendor/` into the same path under `/var/lib/waydroid/overlay/vendor/`, and restart the session.

#### Patch bases

| Repository | Upstream | Branch | Base | Patches |
|---|---|---|---|---|
| `hardware/waydroid` | https://github.com/WayDroid-ATV/android_hardware_waydroid | lineage-23.0 (ATV manifest) | `3af187c1de51` | 29 |
| `external/minigbm` | https://github.com/WayDroid-ATV/android_external_minigbm | lineage-24.0 | `5f5797cacd14` | 9 |
| `hardware/interfaces` | https://github.com/WayDroid-ATV/android_hardware_interfaces | lineage-24.0 | `1b0bcde9a85b` | 1 |
| `external/wayland-protocols` | https://android.googlesource.com/platform/external/wayland-protocols | AOSP | `2dabfe6879b2` | 3 |
| `device/waydroid/waydroid` | https://github.com/WayDroid-ATV/android_device_waydroid_waydroid | lineage-24.0 | `ce2f57ee2768` | 4 |
| `vendor/waydroid/init` | https://github.com/WayDroid-ATV/android_vendor_waydroid_init | lineage-24.0 | `e97b43d97f70` | 2 |
| `waydroid-nvidia` | https://github.com/Shiro836/waydroid-nvidia | public-test | `29ffa3a237b0` | 12 |

### Repository layout

| Path | Contents |
|---|---|
| `patches/<repo>/` | Local commits on each source repository (`git format-patch`) |
| `nvidia-product/` | The `vendor/nvidia-prolapse` product layer, from waydroid-nvidia v0.2.0-rc10, adapted to Android 17 |
| `container/` | Build container |
| `scripts/` | Sync, patch, build and benchmark scripts, written for the author's directory layout |
| `host/` | systemd service that loads KernelSU at boot; the KWin placement script |
| `aur/` | PKGBUILD of the AUR package `waydroid-a17-nvidia-bin` |
| `kernelsu/` | KernelSU steps, the kernelsu-dkms PKGBUILD, and scripts to build and sign the manager |
| `reports/` | Porting notes, comparisons and benchmarks |

### License

Original scripts, documentation and code in this repository are under the [MIT](LICENSE) license. The patches under `patches/` are derivative works and keep their upstream licenses: Apache-2.0 for AOSP, LineageOS and hwcomposer; BSD-3-Clause for minigbm; MIT/HPND for wayland-protocols; GPL-3.0 for the ATV vendor init and Waydroid; waydroid-nvidia's LICENSE (MIT for its original parts) for waydroid-nvidia. `nvidia-product/` keeps waydroid-nvidia's license. The vendor image in Releases contains these projects and their prebuilt components, each under its own license.

### Acknowledgements

- [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia): the nvidia-prolapse mode, the NVK and Rust RM native driver bundle, ANGLE, the NVDEC Codec2 component, and most of the hwcomposer fixes. This project would not exist without it.
- [WayDroid-ATV](https://github.com/WayDroid-ATV) (supechicken): the Android 17 system image and device tree, and KernelSU support for Waydroid ([supechicken/KernelSU](https://github.com/supechicken/KernelSU)).
- [Waydroid](https://github.com/waydroid/waydroid), [LineageOS](https://lineageos.org), [KernelSU](https://github.com/tiann/KernelSU), [Mesa](https://mesa3d.org) (NVK), [ANGLE](https://chromium.googlesource.com/angle/angle).
- The authors of the wayland-protocols `text-input-v3` and `ext-data-control-v1`.

---

## 中文

Waydroid 整合版：Android 17（LineageOS 24.0）+ NVIDIA 显卡硬件加速 + KernelSU root，外加面向 KDE Plasma 的桌面整合。目标是维护一套日常好用的组合，不是通用发行版。

> 个人维护，按现状提供。只在作者的机器上验证过：RTX 4060 Laptop、NVIDIA open 驱动 615.78.08、KDE Plasma 6 Wayland、Arch Linux（zen 内核）。欢迎 issue 和 PR，但不保证回复和支持。

### 组成

| 部分 | 来源 |
|---|---|
| system | [WayDroid-ATV](https://github.com/WayDroid-ATV) 的 LineageOS 24.0 镜像（VANILLA 或 GAPPS），不改 |
| vendor | 本仓库自编：把 [waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia) 的 nvidia-prolapse 模式移植到 ATV lineage-24.0 设备树上，见 Releases |
| 主机侧 | waydroid-nvidia 的 Waydroid，打上 `patches/waydroid-nvidia/` 的补丁 |
| root | 宿主机 `kernelsu-dkms` + 自签名管理器，见 [`kernelsu/README.md`](kernelsu/README.md) |

### 功能

- **NVIDIA 加速**：ANGLE → NVK（双图形队列）→ NVIDIA 内核驱动。HWUI 用 Vulkan 渲染（skiavk）。H.264、HEVC、VP9、AV1 由 NVDEC 硬解。
- **多窗口**：执行 `waydroid prop set persist.waydroid.multi_windows true` 后，每个 Android 应用一个 KDE 窗口，标题栏、拖动、缩放、关闭都由 KWin 处理。`waydroid show-full-ui` 在一个 KDE 窗口里打开 Android 桌面，关掉后应用回到各自的窗口。
- **记住窗口位置**：可选的 KWin 脚本 `host/kwin-waydroid-placement` 让应用窗口重开时回到上次关闭的位置。位置存在 `~/.config/kwin-waydroid-placement.conf`，注销后仍在。
- **宿主输入法**：fcitx5、ibus 等宿主输入法经 Wayland `text-input-v3` 直接在 Android 里输入，候选框跟随光标。Android 侧是预装在 vendor 的输入法 `WaydroidHostIme`，首次开机自动启用。
- **剪贴板**：经 `ext-data-control` 与主机双向同步，不依赖窗口焦点。
- **声音**：经主机 PulseAudio 输出。Android 媒体音量默认最大，音量由主机控制。
- **文件共享**：主机的 `~/Downloads` 出现在 Android 的 `Download/Host`，两边读写同一份文件，Android 新建的文件在主机上归当前用户。主机放进来的文件会自动通知 Android 媒体库。其他目录可在 `/var/lib/waydroid/waydroid.cfg` 的 `[waydroid]` 里用 `shared_folders` 配置：每行一个 `主机目录:存储路径`，存储路径要放在 `Download`、`Pictures` 等标准目录下面。
- **DRM**：Widevine L3（软件实现，无 HDCP），流媒体应用一般只给标清。
- **Google 应用**：用 ATV 的 GAPPS system 镜像即可，vendor 镜像不变。

### 性能

Basemark GPU（Vulkan、3840×2160、Medium、离屏）：宿主用 NVIDIA 官方驱动 35657 分，Waydroid 29369 分，约为宿主的 82%。Android 版 Basemark 只带 ETC2 纹理，显卡不能直接采样，所以驱动本身的差距比这更小。3DMark Wild Life Extreme 约 12300–13100 分（约 74 FPS）。详见 [`reports/`](reports/)。

### 安装（Arch Linux：AUR）

```bash
yay -S waydroid-a17-nvidia-bin
```

包里有打过补丁的 Waydroid 主机部分、本仓库 Release 的 vendor 镜像和与之配套的 native 驱动包，以及 KWin 脚本；不含 Android system 镜像和 KernelSU。装好后：

```bash
Basemark GPU（Vulkan、3840×2160、Medium、离屏）：宿主用 NVIDIA 官方驱动 35657 分，Waydroid 29369 分，约为宿主的 82%。Android 版 Basemark 只带 ETC2 纹理，NVK 不支持直接采样，宿主用的是 BC7，所以这项对比对宿主有利。3DMark Wild Life Extreme 约 12300–13100 分（约 74 FPS）。详见 [`reports/`](reports/)。
# ATV 20261017 的 system 镜像（GAPPS 或 VANILLA）：https://github.com/WayDroid-ATV/waydroid-builds/releases/tag/20261017
sudo bsdtar -xf lineage-24.0-20261017-GAPPS-waydroid_x86_64-system.zip -C /etc/waydroid-extra/images system.img
sudo bsdtar -xf /usr/lib/waydroid-nvidia/vendor/waydroid-nvidia-vendor-x86_64-*.zip -C /etc/waydroid-extra/images vendor.img
sudo waydroid init -f
sudo waydroid-nvidia-setup        # 在本机 GPU 和内核模块上跑发布门禁，通过后装上 vendor 镜像
waydroid prop set persist.waydroid.multi_windows true
waydroid session start
```

需要 NVIDIA open 内核模块（作者用 615.78.08）和 binder（binderfs）。NVIDIA 驱动更新并重启后，要再跑一次 `sudo waydroid-nvidia-setup`。KWin 脚本在「系统设置 → 窗口管理 → KWin 脚本」里启用「Waydroid card placement」。root 见 [`kernelsu/`](kernelsu/)。

### 手动安装

其他发行版从 Releases 取这两样：

- vendor 镜像，分块上传：
  ```bash
  cat vendor.img.zst.part* > vendor.img.zst && zstd -d vendor.img.zst
  sha256sum -c vendor.img.zst.sha256   # 校验分块、压缩包和解压后的镜像
  ```
- native 驱动包 `waydroid-a17-nvidia-native-x86_64.tar.zst`，必须和 vendor 镜像同一版。

然后：

1. 按 waydroid-nvidia `public-test` 分支的 README 安装主机部分，安装前在它的源码上 `git am patches/waydroid-nvidia/*.patch`。把 native 驱动包解压到 `/usr/lib/waydroid-nvidia/native/release/`。
2. 从 ATV 的 `lineage-24.0-*-waydroid_x86_64-system.zip` 解出 `system.img`。
3. 把 `system.img` 和 `vendor.img` 放进 Waydroid 的镜像目录（如 `/etc/waydroid-extra/images/`），再运行 `waydroid-nvidia-setup`。

具体的文件布局可以参考 `aur/waydroid-a17-nvidia-bin/PKGBUILD`。

### 从源码构建

需要 podman 和充足的磁盘：源码约 100 GB，另加编译输出。完整编译 vendor 镜像要数小时；有 ccache 后，重编单个库只要几分钟。

1. 编译容器：`podman build --build-arg ROOT="$PWD" -t localhost/waydroid-a17-build container`。`scripts/build.sh` 把项目目录按原路径挂进容器，因为 Mesa 交叉编译要用树里的 lld。
2. `scripts/sync.sh`：同步 LineageOS 24.0 和 ATV manifest 到 `src/`，再执行 `apply-waydroid-patches`。
3. 在下表各仓库的基线上 `git am patches/<仓库>/*.patch`，把 `nvidia-product/` 复制到 `src/vendor/nvidia-prolapse`。
4. `scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug vendorimage`

只想测一个模块时，单独编它（例如 `hwcomposer.waydroid`），把 `out/.../vendor/` 下的文件放进 `/var/lib/waydroid/overlay/vendor/` 的相同路径，重启会话即可。

#### 补丁基线

| 仓库 | 上游 | 分支 | 基线 | 补丁数 |
|---|---|---|---|---|
| `hardware/waydroid` | https://github.com/WayDroid-ATV/android_hardware_waydroid | lineage-23.0 (ATV manifest) | `3af187c1de51` | 29 |
| `external/minigbm` | https://github.com/WayDroid-ATV/android_external_minigbm | lineage-24.0 | `5f5797cacd14` | 9 |
| `hardware/interfaces` | https://github.com/WayDroid-ATV/android_hardware_interfaces | lineage-24.0 | `1b0bcde9a85b` | 1 |
| `external/wayland-protocols` | https://android.googlesource.com/platform/external/wayland-protocols | AOSP | `2dabfe6879b2` | 3 |
| `device/waydroid/waydroid` | https://github.com/WayDroid-ATV/android_device_waydroid_waydroid | lineage-24.0 | `ce2f57ee2768` | 4 |
| `vendor/waydroid/init` | https://github.com/WayDroid-ATV/android_vendor_waydroid_init | lineage-24.0 | `e97b43d97f70` | 2 |
| `waydroid-nvidia` | https://github.com/Shiro836/waydroid-nvidia | public-test | `29ffa3a237b0` | 12 |

### 目录

| 路径 | 内容 |
|---|---|
| `patches/<仓库>/` | 各源码仓库上的本地提交（`git format-patch`） |
| `nvidia-product/` | `vendor/nvidia-prolapse` product 层，来自 waydroid-nvidia v0.2.0-rc10，已适配 Android 17 |
| `container/` | 编译容器 |
| `scripts/` | 同步、打补丁、编译、跑分脚本，按作者本机的目录布局写的 |
| `host/` | 宿主机开机加载 KernelSU 的 systemd 服务；记住窗口位置的 KWin 脚本 |
| `aur/` | AUR 包 `waydroid-a17-nvidia-bin` 的 PKGBUILD |
| `kernelsu/` | KernelSU 步骤、kernelsu-dkms PKGBUILD、管理器编译与签名脚本 |
| `reports/` | 移植记录、对比和性能报告 |

### 许可证

本仓库原创的脚本、文档和代码按 [MIT](LICENSE) 提供。`patches/` 下的补丁是各上游的派生作品，沿用上游许可证：AOSP、LineageOS 与 hwcomposer 为 Apache-2.0，minigbm 为 BSD-3-Clause，wayland-protocols 为 MIT/HPND，ATV vendor init 与 Waydroid 为 GPL-3.0，waydroid-nvidia 按其 LICENSE（原创部分 MIT）。`nvidia-product/` 沿用 waydroid-nvidia 的许可证。Releases 中的 vendor 镜像包含上述各项目及其预编译组件，分别遵循各自的许可证。

### 致谢

- [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)：nvidia-prolapse 模式、NVK 与 Rust RM 原生驱动包、ANGLE、NVDEC Codec2 组件，以及大部分 hwcomposer 修正。没有它就没有这个项目。
- [WayDroid-ATV](https://github.com/WayDroid-ATV)（supechicken）：Android 17 system 镜像与设备树；KernelSU 的 Waydroid 支持（[supechicken/KernelSU](https://github.com/supechicken/KernelSU)）。
- [Waydroid](https://github.com/waydroid/waydroid)、[LineageOS](https://lineageos.org)、[KernelSU](https://github.com/tiann/KernelSU)、[Mesa](https://mesa3d.org)（NVK）、[ANGLE](https://chromium.googlesource.com/angle/angle)。
- wayland-protocols 中 `text-input-v3`、`ext-data-control-v1` 的作者们。
