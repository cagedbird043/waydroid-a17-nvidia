# TODO

当前状态、测试结果和移植记录见 `reports/porting.md`；构建、测试、发版流程见 `.agents/skills/`。

## 现状（2026-10-28）

- system：ATV LineageOS 24.0 GAPPS 版 `20261017`，Play 商店已认证。
- vendor：自编 nvidia-prolapse；ANGLE → NVK，HWUI skiavk，NVDEC 硬解，NVENC 硬编（H.264/HEVC/AV1，Chrome WebCodecs 与 WebRTC 已实测）。
- Codec2 编码核心使用 Rust，五种输入格式与 H.264/HEVC/AV1 已验证；能力枚举与 XML 使用同一快照，组件列表保持 4 解码 + 3 编码。
- Codec2 seccomp 策略补齐日志 socket/connect 权限；冷启动与稳态 syscall 按实参核对，Surface 解码与网页编码有独立回归门禁。
- Codec2 解码驱动使用 Rust：多显示帧逐帧交付；启动/回放 CSD 上限 2 MiB；gralloc 外壳、元数据与平面范围完整校验。VP9 superframe 的 ByteBuffer/Surface 两条路径与 Chrome 60 秒 VP9 播放已实测。
- 多窗口（`persist.waydroid.multi_windows=true`）：freeform 卡片 + 带 KDE 边框的桌面窗口。
- 宿主输入法：text-input-v3 → `WaydroidHostIme`。
- 剪贴板：ext-data-control，主机复制经输入法推送进 Android；主机侧 Python 剪贴板服务已删除。
- 文件共享：主机 `~/Downloads` 挂在 Android `Download/Host`（`waydroid.cfg` 的 `shared_folders` 可改），主机侧改动自动进媒体库。
- 声音：经主机 PulseAudio 输出；网页音频等 AAudio 流也有声（不声明 MMAP），媒体音量默认最大，由主机控制音量。
- Widevine：L3（`dumpsys android.hardware.drm.IDrmFactory/widevine`：`default_security_level: L3`，`hdcp_level_max: Unprotected`），无法提升。
- root：KernelSU LKM，本地签名管理器 32708。
- ABI：`x86_64, arm64-v8a, x86`，ARM 翻译用 ATV 自带的 `libndk_translation`，没有 `armeabi-v7a`。

## 功能

1. **重负载实测**：3DMark Wild Life Extreme（Vulkan，4K）12287–13096 分、约 74 FPS，无 Xid，同一进程连续多遍稳定。Basemark GPU（Vulkan 1.0、4K、Medium、离屏、Z Prepass 关）：宿主官方驱动 35657（BC7），Waydroid 29369（ETC2），约 82%。还没测真实 3D 游戏。
2. **跟进 libvulkan 上游修复**：A17 loader 的 R8G8B8 swapchain 检查直接调用 1.1 的 `GetPhysicalDeviceImageFormatProperties2` 原始指针，1.0 实例为空即崩；本仓库靠 gralloc 不声称 BGR888 可渲染（`patches/external_minigbm/0009`）绕开。loader 修复已提交 LineageOS Gerrit（[509993](https://review.lineageos.org/c/LineageOS/android_frameworks_native/+/509993)）并报给 Google（[b/577380015](https://issuetracker.google.com/issues/577380015)），等审核。
3. **下个版本门禁工具预检**：门禁开跑前检查 `dump.erofs` / `debugfs` / `readelf` / `unshare` 等所需工具，缺失时明确报出对应 Arch 包名，避免裸 `Errno 2`。

## 不做

- **整版跟进 waydroid-nvidia**：本仓库是分叉（自编双队列 NVK、主机侧补丁、自编 vendor），不随上游 rc 版本 rebase。上游有用的修复读懂后移植过来；NVIDIA 驱动升级后门禁不过时先看上游怎么修的。已移植到 rc11（`7670f54`）。ATV 出新 system 镜像时单独评估。Codec2 的解码、能力表/XML 已换成 Rust，上游对应的 C++ 修复要在 Rust 里重写，边界见 `reports/codec2-rust.md`。

- **32 位 ARM（`armeabi-v7a`）**：现在的应用基本都有 arm64 版本（Play 早已要求 64 位，新手机也已不支持 32 位应用）。ATV A17 镜像只带 arm64 翻译；ATV 的 `vendor_google_proprietary_ndk_translation-prebuilt` 在 `16arm_16arm64` 分支上有 32 位库，但那是 Android 16 的。
- **桌面窗口和卡片同时开**：两者共用一块 Android 屏幕，只能二选一。卡片加主机菜单里的 Android 应用启动项已经覆盖日常用法；只有用桌面小部件、或个别应用当卡片用有问题时才需要桌面窗口，临时切过去即可。

## 卡片模式与输入法的已知问题

1. **卡片共用一块 Android 屏幕**：显示尺寸 = 宿主 + 200 headroom，窗口多时可能互相遮挡点击区域。
2. **内嵌预编辑不显示**：fcitx5 用 Ctrl+Alt+P 打开内嵌预编辑后，Android 和 KWrite 一样，拼音仍只在候选框里，问题在 fcitx5/KWin 一侧。

