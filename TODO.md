# TODO

当前状态、测试结果和移植记录见 `reports/porting.md`。

## 现状（2026-10-24）

- system：ATV LineageOS 24.0 GAPPS 版 `20261017`，Play 商店已认证。
- vendor：自编 nvidia-prolapse；ANGLE → NVK，HWUI skiavk，NVDEC 硬解。
- 多窗口（`persist.waydroid.multi_windows=true`）：freeform 卡片 + 带 KDE 边框的桌面窗口。
- 宿主输入法：text-input-v3 → `WaydroidHostIme`。
- 剪贴板：ext-data-control，主机复制经输入法推送进 Android；主机侧 Python 剪贴板服务已删除。
- 文件共享：主机 `~/Downloads` 挂在 Android `Download/Host`（`waydroid.cfg` 的 `shared_folders` 可改）。
- root：KernelSU LKM，本地签名管理器 32708。
- ABI：`x86_64, arm64-v8a, x86`，ARM 翻译用 ATV 自带的 `libndk_translation`，没有 `armeabi-v7a`。

## 发版

1. **发版流程**：完整编 vendorimage → 删掉 `/var/lib/waydroid/overlay/vendor` 里调试用的文件 → `scripts/reinstall-vendor.sh`（含门禁）→ 回归（卡片、桌面窗口、输入法、剪贴板、KernelSU）→ 分块上传 Release。
2. **AUR**：暂缓。计划拆成 `waydroid-a17-nvidia`（打过补丁的 Waydroid 主机部分，`conflicts=(waydroid)`）和 `waydroid-a17-nvidia-vendor-bin`（从 Release 下载 vendor 镜像）；KernelSU 不进 AUR（签名因人而异）。先看 waydroid-nvidia 的 `ci-aur` 分支，避免重复。

## 功能

1. **重负载实测**：glmark2 太轻；换真实 3D 游戏或 GFXBench，看性能和稳定性，同时盯 Xid。
2. **界面微调**：隐藏状态栏、smartdock 之类，用 KernelSU 模块或 `waydroid prop`，不改镜像。
3. **Widevine**：vendor 带 `drm-service.widevine`，级别未实测，推测 L3（Netflix 之类只有标清），无法提升。
4. **跟进上游**：ATV 出新 system 镜像、waydroid-nvidia 出 rc11 时 rebase 重编（`scripts/apply-nvidia.sh`、`scripts/build.sh`、`scripts/reinstall-vendor.sh`）。
5. **主机文件进图库**：主机放进共享目录的文件，文件管理器和系统文件选择器立即可见，但要等 MediaStore 扫描后图库才列出（`content call --uri content://media --method scan_volume --arg external_primary` 可手动触发）。

## 不做

- **32 位 ARM（`armeabi-v7a`）**：现在的应用基本都有 arm64 版本（Play 早已要求 64 位，新手机也已不支持 32 位应用）。ATV A17 镜像只带 arm64 翻译；ATV 的 `vendor_google_proprietary_ndk_translation-prebuilt` 在 `16arm_16arm64` 分支上有 32 位库，但那是 Android 16 的。

## 卡片模式与输入法的已知问题

1. **缩放时内容滞后**：拖动 KDE 窗口边框时窗口先变，Android 要等 `cmd` 调整任务尺寸、应用重新排版后才跟上。可试：拖动期间先按比例缩放旧画面占位，或合并多次 resize。
2. **卡片共用一块 Android 屏幕**：显示尺寸 = 宿主 + 200 headroom，窗口多时可能互相遮挡点击区域；卡片和桌面窗口只能二选一。根治需要每个窗口一个虚拟显示，改动大。
3. **卡片位置只在本次 KWin 会话内记住**：`host/kwin-waydroid-placement` 把关闭时的位置按 app_id 记在内存里，注销后清空。
4. **内嵌预编辑不显示**：fcitx5 用 Ctrl+Alt+P 打开内嵌预编辑后，Android 和 KWrite 一样，拼音仍只在候选框里，问题在 fcitx5/KWin 一侧。

## 维护备忘

- 重装用 `scripts/reinstall-vendor.sh`，它会把 `debug.hwui.renderer` 写回 `skiavk`。
- 清空 Waydroid data 后要重新放 `/data/adb/ksud`、装管理器（`kernelsu/README.md` 第 5 步），并重新 `waydroid prop set persist.waydroid.multi_windows true`。
- `nvidia/waydroid-nvidia` 中 `eec39aa` 及之前的提交不能重写：native bundle 的 BUILD-RECORD 记着从 `eec39aa` 编出，`install.sh --source` 要求本地源码是它的后代。
- 调试：`setprop waydroid.dump_hal 1`（下一帧打印图层、任务、窗口）；`waydroid prop set persist.waydroid.clipboard_debug true` 后重启会话（logcat `hwcomposer` 的 `clipboard:` 行）。
