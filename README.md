# Waydroid A17 NVIDIA

Waydroid 整合版：Android 17（LineageOS 24.0）+ NVIDIA 显卡硬件加速 + KernelSU root，外加桌面体验上的改进。目标是维护一套日常好用的组合，不是通用发行版。

> 个人维护，按现状提供。只在作者的机器上验证过（RTX 4060 Laptop、驱动 615.78.08 open、KDE Plasma 6 Wayland、Arch/zen 内核）。欢迎 issue 和 PR，但不保证回复和支持。

## 组成

| 部分 | 来源 |
|---|---|
| system | [WayDroid-ATV](https://github.com/WayDroid-ATV) 的 LineageOS 24.0 镜像（VANILLA 或 GAPPS），不改 |
| vendor | 在 ATV lineage-24.0 设备树上移植 [waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia) 的 nvidia-prolapse 模式后自编，见 Releases |
| 主机侧 | waydroid-nvidia 打过补丁的 Waydroid（`patches/waydroid-nvidia/`） |
| root | 宿主机 `kernelsu-dkms` + 自签名管理器，见 [`kernelsu/README.md`](kernelsu/README.md) |

## 功能

- **NVIDIA 加速**：ANGLE → NVK（双图形队列）→ NVIDIA 内核驱动；HWUI 走 Vulkan（skiavk）；H.264/HEVC/VP9/AV1 由 NVDEC 硬解。
- **多窗口**：`waydroid prop set persist.waydroid.multi_windows true` 后，每个 Android 应用一个 KDE 窗口（freeform 卡片），标题栏、拖动、缩放、关闭都由 KWin 处理；`waydroid show-full-ui` 打开带 KDE 边框的 Android 桌面窗口，关掉后应用回到各自窗口。可选的 KWin 脚本 `host/kwin-waydroid-placement` 让重开的卡片回到上次关闭的位置（存在 `~/.config/kwin-waydroid-placement.conf`，注销后仍在）：`kpackagetool6 --type KWin/Script --install host/kwin-waydroid-placement && kwriteconfig6 --file kwinrc --group Plugins --key waydroid-placementEnabled true && qdbus6 org.kde.KWin /KWin reconfigure`。
- **宿主输入法**：fcitx5、ibus 等经 Wayland `text-input-v3` 直接在 Android 里输入，候选框跟随光标。Android 侧是预装在 vendor 的输入法 `WaydroidHostIme`，开机自动启用。
- **剪贴板**：经 `ext-data-control` 与主机双向同步，不依赖窗口焦点；不再需要主机侧 Python 剪贴板服务。
- **文件共享**：主机 `~/Downloads` 出现在 Android 的 `Download/Host`，两边读写同一份文件，Android 新建的文件在主机上归当前用户。可在 `/var/lib/waydroid/waydroid.cfg` 的 `[waydroid]` 里用 `shared_folders` 改成别的目录或加更多目录（每行一个 `主机目录:存储路径`，存储路径要放在 `Download`、`Pictures` 等标准目录下面）。主机放进共享目录的文件会自动通知 Android 媒体库，图库里直接能看到。
- **DRM**：Widevine L3（软件实现，无 HDCP），流媒体应用一般只给标清。
- **GApps**：直接用 ATV 的 GAPPS system 镜像，vendor 不变。

已知问题和计划见 [`TODO.md`](TODO.md)，详细的移植记录、测试结果和性能数据见 [`reports/porting.md`](reports/porting.md)。

## 使用预编译 vendor 镜像

Releases 里的 vendor 镜像分块上传：

```bash
cat vendor.img.zst.part* > vendor.img.zst && zstd -d vendor.img.zst
sha256sum -c vendor.img.zst.sha256   # 校验分块、压缩包和解压后的镜像
```

需要：
1. NVIDIA open 内核模块（作者用 615.78.08）和 binder（binderfs）。
2. waydroid-nvidia 主机部分：按其 `public-test` 分支 README 安装，安装前在其源码上 `git am patches/waydroid-nvidia/*.patch`（A17 vendor 支持、KernelSU seccomp、去掉 Python 剪贴板服务、文件共享等）。vendor 与它的 native bundle（v0.2.0-rc10）配套。
3. ATV 的 `lineage-24.0-*-waydroid_x86_64-system.zip`，解出 `system.img`。
4. 把 `system.img` 和本仓库的 `vendor.img` 放进 Waydroid 的镜像目录（如 `/etc/waydroid-extra/images/`），再运行 `waydroid-nvidia-setup`（发布门禁 + 安装）。作者本机的完整流程是 `scripts/reinstall-vendor.sh`。

## 从源码构建

需要 podman 和充足磁盘（源码约 100 GB，另加编译输出），编译整个 vendor 镜像数小时（有 ccache 后单个库几分钟）。

1. 编译容器：`podman build --build-arg ROOT="$PWD" -t localhost/waydroid-a17-build container`（`scripts/build.sh` 把项目目录按原路径挂进容器，Mesa 交叉编译要用树里的 lld）。
2. `scripts/sync.sh`：同步 LineageOS 24.0 + ATV manifest 到 `src/`，再 `apply-waydroid-patches`。
3. 在下表各仓库的基线上 `git am patches/<仓库>/*.patch`；`nvidia-product/` 放到 `src/vendor/nvidia-prolapse`。（作者本机用 `scripts/apply-nvidia.sh` 从本地克隆 cherry-pick，效果相同。）
4. `scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug vendorimage`

只改 hwcomposer 时，`scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug hwcomposer.waydroid` 后把 `out/.../vendor/lib64/hw/hwcomposer.waydroid.so` 装进 `/var/lib/waydroid/overlay/vendor/lib64/hw/`，重启会话即可，不用重做镜像。

### 补丁基线

| 仓库 | 上游 | 分支 | 基线 | 补丁数 |
|---|---|---|---|---|
| `hardware/waydroid` | https://github.com/WayDroid-ATV/android_hardware_waydroid | lineage-23.0 (ATV manifest) | `3af187c1de51` | 29 |
| `external/minigbm` | https://github.com/WayDroid-ATV/android_external_minigbm | lineage-24.0 | `5f5797cacd14` | 8 |
| `hardware/interfaces` | https://github.com/WayDroid-ATV/android_hardware_interfaces | lineage-24.0 | `1b0bcde9a85b` | 1 |
| `external/wayland-protocols` | https://android.googlesource.com/platform/external/wayland-protocols | AOSP | `2dabfe6879b2` | 3 |
| `device/waydroid/waydroid` | https://github.com/WayDroid-ATV/android_device_waydroid_waydroid | lineage-24.0 | `ce2f57ee2768` | 3 |
| `vendor/waydroid/init` | https://github.com/WayDroid-ATV/android_vendor_waydroid_init | lineage-24.0 | `e97b43d97f70` | 2 |
| `waydroid-nvidia` | https://github.com/Shiro836/waydroid-nvidia | public-test | `29ffa3a237b0` | 12 |

## 目录

| 路径 | 内容 |
|---|---|
| `patches/<仓库>/` | 各源码仓库上的本地提交（`git format-patch`） |
| `nvidia-product/` | `vendor/nvidia-prolapse` product 层（来自 waydroid-nvidia v0.2.0-rc10，已适配 A17） |
| `container/` | 编译容器 |
| `scripts/` | 同步、打补丁、编译、重装 vendor、跑分（按作者本机目录布局写的） |
| `host/` | 宿主机开机加载 KernelSU 的 systemd 服务；记住卡片位置的 KWin 脚本 |
| `kernelsu/` | KernelSU 步骤、kernelsu-dkms PKGBUILD、管理器编译与签名脚本 |
| `reports/` | 移植、对比、性能报告 |

## 许可证

本仓库原创的脚本、文档和代码按 [MIT](LICENSE) 提供。`patches/` 下的补丁是各上游的派生作品，沿用上游许可证：AOSP/LineageOS 与 hwcomposer 为 Apache-2.0，minigbm 为 BSD-3-Clause，wayland-protocols 为 MIT/HPND，ATV vendor init 与 Waydroid 为 GPL-3.0，waydroid-nvidia 按其 LICENSE（原创部分 MIT）。`nvidia-product/` 沿用 waydroid-nvidia 的许可证。Releases 中的 vendor 镜像包含上述各项目及其预编译组件，分别遵循各自许可证。

## 致谢

- [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)：nvidia-prolapse 模式、NVK/Rust RM 原生驱动包、ANGLE、NVDEC Codec2，以及大部分 hwcomposer 修正。没有它就没有这个项目。
- [WayDroid-ATV](https://github.com/WayDroid-ATV)（supechicken）：Android 17 system 镜像与设备树；KernelSU 的 Waydroid 支持（[supechicken/KernelSU](https://github.com/supechicken/KernelSU)）。
- [Waydroid](https://github.com/waydroid/waydroid)、[LineageOS](https://lineageos.org)、[KernelSU](https://github.com/tiann/KernelSU)、[Mesa](https://mesa3d.org)（NVK）、[ANGLE](https://chromium.googlesource.com/angle/angle)。
- wayland-protocols：`text-input-v3`、`ext-data-control-v1` 的作者们。
