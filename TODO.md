# TODO

当前状态、测试结果和移植记录见 `reports/porting.md`。

## 现状（2026-10-24）

- system：ATV LineageOS 24.0 GAPPS 版 `20261017`，Play 商店已认证。
- vendor：自编 nvidia-prolapse；ANGLE → NVK，HWUI skiavk，NVDEC 硬解。
- 多窗口（`persist.waydroid.multi_windows=true`）：freeform 卡片 + 带 KDE 边框的桌面窗口。
- 宿主输入法：text-input-v3 → `WaydroidHostIme`。
- 剪贴板：ext-data-control，主机复制经输入法推送进 Android；主机侧 Python 剪贴板服务已删除。
- 文件共享：主机 `~/Downloads` 挂在 Android `Download/Host`（`waydroid.cfg` 的 `shared_folders` 可改），主机侧改动自动进媒体库。
- 声音：经主机 PulseAudio 输出；网页音频等 AAudio 流也有声（不声明 MMAP），媒体音量默认最大，由主机控制音量。
- Widevine：L3（`dumpsys android.hardware.drm.IDrmFactory/widevine`：`default_security_level: L3`，`hdcp_level_max: Unprotected`），无法提升。
- root：KernelSU LKM，本地签名管理器 32708。
- ABI：`x86_64, arm64-v8a, x86`，ARM 翻译用 ATV 自带的 `libndk_translation`，没有 `armeabi-v7a`。

## 发版

1. **发版流程**：完整编 vendorimage → 删掉 `/var/lib/waydroid/overlay/vendor` 里调试用的所有文件（`sudo find /var/lib/waydroid/overlay/vendor -type f` 列出）→ 压缩分块、打 native bundle → 放进 `aur/waydroid-a17-nvidia-bin/`（文件名与 `source` 一致，makepkg 不再下载）改 `_tag`/`pkgver`、`updpkgsums`、`makepkg -fC`、`sudo pacman -U` → `sudo waydroid-nvidia-setup`（门禁）→ 回归（卡片、桌面窗口、输入法、剪贴板、文件共享、KernelSU）→ 打 tag、上传 Release → 删掉本地放的文件后 `makepkg -fC` 再验一遍下载 → `.SRCINFO`、推 AUR。
2. **AUR**：`waydroid-a17-nvidia-bin`（`aur/` 目录）。每次发版后改 `_tag`/`pkgver`，`updpkgsums`，`makepkg --printsrcinfo > .SRCINFO`，推到 `ssh://aur@aur.archlinux.org/waydroid-a17-nvidia-bin.git`。native bundle 作为 Release 资产 `waydroid-a17-nvidia-native-x86_64.tar.zst` 一起上传。

## 功能

1. **重负载实测**：3DMark Wild Life Extreme（Vulkan，4K）12287–13096 分、约 74 FPS，无 Xid，同一进程连续多遍稳定。Basemark GPU（Vulkan 1.0、4K、Medium、离屏、Z Prepass 关）：宿主官方驱动 35657（BC7），Waydroid 29369（ETC2），约 82%。还没测真实 3D 游戏。
2. **跟进 libvulkan 上游修复**：A17 loader 的 R8G8B8 swapchain 检查直接调用 1.1 的 `GetPhysicalDeviceImageFormatProperties2` 原始指针，1.0 实例为空即崩；本仓库靠 gralloc 不声称 BGR888 可渲染（`patches/external_minigbm/0009`）绕开。loader 修复已提交 LineageOS Gerrit（[509993](https://review.lineageos.org/c/LineageOS/android_frameworks_native/+/509993)）并报给 Google（[b/577380015](https://issuetracker.google.com/issues/577380015)），等审核。

## 不做

- **整版跟进 waydroid-nvidia**：本仓库是分叉（自编双队列 NVK、主机侧补丁、自编 vendor），不随上游 rc 版本 rebase。上游有用的修复读懂后移植过来；NVIDIA 驱动升级后门禁不过时先看上游怎么修的。已移植到 rc11（`7670f54`）。ATV 出新 system 镜像时单独评估。

- **32 位 ARM（`armeabi-v7a`）**：现在的应用基本都有 arm64 版本（Play 早已要求 64 位，新手机也已不支持 32 位应用）。ATV A17 镜像只带 arm64 翻译；ATV 的 `vendor_google_proprietary_ndk_translation-prebuilt` 在 `16arm_16arm64` 分支上有 32 位库，但那是 Android 16 的。
- **桌面窗口和卡片同时开**：两者共用一块 Android 屏幕，只能二选一。卡片加主机菜单里的 Android 应用启动项已经覆盖日常用法；只有用桌面小部件、或个别应用当卡片用有问题时才需要桌面窗口，临时切过去即可。

## 卡片模式与输入法的已知问题

1. **卡片共用一块 Android 屏幕**：显示尺寸 = 宿主 + 200 headroom，窗口多时可能互相遮挡点击区域。
2. **内嵌预编辑不显示**：fcitx5 用 Ctrl+Alt+P 打开内嵌预编辑后，Android 和 KWrite 一样，拼音仍只在候选框里，问题在 fcitx5/KWin 一侧。

## 维护备忘

- 本机的 Waydroid 由 pacman 包 `waydroid-a17-nvidia-bin` 管理；`scripts/reinstall-vendor.sh`（走 `install.sh`）会因文件归 pacman 所有而拒绝安装，重装走上面的 makepkg 流程。
- 清空 Waydroid data 后要重新放 `/data/adb/ksud`、装管理器（`kernelsu/README.md` 第 5 步），并重新 `waydroid prop set persist.waydroid.multi_windows true`。
- `nvidia/waydroid-nvidia` 中 `eec39aa` 及之前的提交不能重写：native bundle 的 BUILD-RECORD 记着从 `eec39aa` 编出，`install.sh --source` 要求本地源码是它的后代。
- 只重编 NVK 和 Rust RM（几十秒，增量）：在 `nvidia/waydroid-nvidia` 下 `podman run --rm --userns=keep-id --network=none -v $PWD:/work -w /work -e HOME=/work/build/.buildenv-home -e CARGO_HOME=/work/build/.buildenv-home/cargo localhost/nvk-native-a17 python3 nvidia-prolapse/driver-source/native/mesa/build.py --target android --rust-profile release -j 14`（32 位用 `--target android32`）；产物 `build/nvk-{android,android32}/src/nouveau/vulkan/libvulkan_nouveau.so` 和 `build/nv-rm-rust/{x86_64,i686}-linux-android/release/libnv_bionic_native.so`，测试时装进 overlay 的 `vendor/lib64/`、`vendor/lib/`。
- Codec2 NVDEC 服务在 A17 树里编（`nvidia-product/vendor/nvidia-prolapse/Android.bp`，源码由 `scripts/stage-product.sh` 放进 `media-src/`）：`scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug android.hardware.media.c2@1.2-service-nvprolapse`。native bundle 的 `payload/odm/bin/hw/` 放这个产物（门禁要求镜像里的服务与 bundle 逐字节一致），所以改了服务要编两遍：先编服务、放进 bundle、更新钉选，再编 vendorimage。安卓内测试用 `nvidia-prolapse/media` 的 `make c2-smoke`，推到 `/data/local/tmp` 后 `c2_smoke <视频.mp4>`。
- 调试：`setprop waydroid.dump_hal 1`（下一帧打印图层、任务、窗口）；`waydroid prop set persist.waydroid.clipboard_debug true` 后重启会话（logcat `hwcomposer` 的 `clipboard:` 行）。
