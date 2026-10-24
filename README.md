# Waydroid A17 NVIDIA

Waydroid 上运行 Android 17（LineageOS 24.0），NVIDIA 显卡硬件加速，KernelSU root。

- system：[WayDroid-ATV](https://github.com/WayDroid-ATV) 发布的 LineageOS 24.0 镜像，不改。
- vendor：在 ATV 的 lineage-24.0 设备树上，移植 [waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)（nvidia-prolapse 模式：NVK + ANGLE，NVDEC 视频解码）后自编。
- root：宿主机 `kernelsu-dkms` + 本地签名的 KernelSU 管理器。

在此之上新增：

- **多窗口**：每个 Android 应用一个 KDE 窗口（freeform 卡片），拖动、缩放、关闭都由 KWin 处理；`waydroid show-full-ui` 打开带 KDE 边框的 Android 桌面窗口。
- **宿主输入法直通**：fcitx5、ibus 等经 Wayland `text-input-v3` 在 Android 里输入，候选框跟随光标。输入法桥是 vendor 应用 `WaydroidHostIme`。
- **剪贴板**：经 ext-data-control 与主机双向同步，不依赖窗口焦点；不再需要主机侧 Python 剪贴板服务。

详细记录见 `reports/porting.md`，待改进见 `TODO.md`。

## 目录

| 路径 | 内容 |
|---|---|
| `patches/<仓库>/` | 各源码仓库上的本地提交（`git format-patch`），按下表的基线提交 `git am` |
| `nvidia-product/` | `vendor/nvidia-prolapse` product 层（来自 waydroid-nvidia v0.2.0-rc10，已适配 A17） |
| `container/` | 编译容器 |
| `scripts/` | 同步、打补丁、编译、重装 vendor、跑分 |
| `host/` | 宿主机开机加载 KernelSU 的 systemd 服务 |
| `kernelsu/` | kernelsu-dkms PKGBUILD（含本地管理器签名哈希）、管理器编译与签名脚本（密钥不在仓库里） |
| `reports/` | 移植、对比、性能报告 |

## 补丁基线

| 仓库 | 上游 | 分支 | 基线 | 补丁数 |
|---|---|---|---|---|
| `hardware/waydroid` | https://github.com/WayDroid-ATV/android_hardware_waydroid | lineage-23.0 (ATV manifest) | `3af187c1de51` | 25 |
| `external/minigbm` | https://github.com/WayDroid-ATV/android_external_minigbm | lineage-24.0 | `5f5797cacd14` | 8 |
| `hardware/interfaces` | https://github.com/WayDroid-ATV/android_hardware_interfaces | lineage-24.0 | `1b0bcde9a85b` | 1 |
| `external/wayland-protocols` | https://android.googlesource.com/platform/external/wayland-protocols | AOSP (TUNA mirror) | `2dabfe6879b2` | 3 |
| `device/waydroid/waydroid` | https://github.com/WayDroid-ATV/android_device_waydroid_waydroid | lineage-24.0 | `ce2f57ee2768` | 2 |
| `vendor/waydroid/init` | https://github.com/WayDroid-ATV/android_vendor_waydroid_init | lineage-24.0 | `e97b43d97f70` | 2 |
| `waydroid-nvidia` | https://github.com/Shiro836/waydroid-nvidia | public-test | `29ffa3a237b0` | 10 |

## 构建

1. `scripts/sync.sh` 同步 LineageOS 24.0 + ATV manifest。
2. 按上表把 `patches/` 打到对应仓库，`nvidia-product/` 放到 `vendor/nvidia-prolapse`（`scripts/stage-product.sh`、`scripts/apply-nvidia.sh`）。
3. `scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug vendorimage`
4. `scripts/reinstall-vendor.sh` 安装。

预编译 vendor 镜像见 Releases。

## 许可证

各补丁沿用对应上游的许可证（AOSP/LineageOS 为 Apache-2.0，minigbm 为 BSD-3-Clause，Waydroid 与 ATV vendor init 为 GPL-3.0）。waydroid-nvidia 的原创部分为 MIT，见其 LICENSE。本仓库原创的脚本与文档按 MIT 提供。

## 致谢

- [Shiro836/waydroid-nvidia](https://github.com/Shiro836/waydroid-nvidia)：NVIDIA 加速
- [WayDroid-ATV](https://github.com/WayDroid-ATV)（supechicken）：Android 17 镜像与设备树，KernelSU 的容器支持
- [Waydroid](https://github.com/waydroid/waydroid)
