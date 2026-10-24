# TODO

当前状态、测试结果和移植记录见 `reports/porting.md`。

## 现状（2026-10-24）

- system：ATV LineageOS 24.0 GAPPS 版 `20261017`，Play 商店已认证。
- vendor：自编 nvidia-prolapse；ANGLE → NVK，HWUI skiavk，NVDEC 硬解。
- 多窗口（`persist.waydroid.multi_windows=true`）：freeform 卡片 + 带 KDE 边框的桌面窗口。
- 宿主输入法：text-input-v3 → `WaydroidHostIme`。
- 剪贴板：ext-data-control，主机复制经输入法推送进 Android；主机侧 Python 剪贴板服务已删除。
- root：KernelSU LKM，本地签名管理器 32708。
- ABI：`x86_64, arm64-v8a, x86`，ARM 翻译用 ATV 自带的 `libndk_translation`，没有 `armeabi-v7a`。

## 发版

1. **发版流程**：完整编 vendorimage → 删掉 `/var/lib/waydroid/overlay/vendor` 里调试用的文件 → `scripts/reinstall-vendor.sh`（含门禁）→ 回归（卡片、桌面窗口、输入法、剪贴板、KernelSU）→ 分块上传 Release。
2. **AUR**：暂缓。计划拆成 `waydroid-a17-nvidia`（打过补丁的 Waydroid 主机部分，`conflicts=(waydroid)`）和 `waydroid-a17-nvidia-vendor-bin`（从 Release 下载 vendor 镜像）；KernelSU 不进 AUR（签名因人而异）。先看 waydroid-nvidia 的 `ci-aur` 分支，避免重复。

## 功能

1. **文件共享**：把主机 `~/Downloads` 等目录挂进 Android 存储。
2. **32 位 ARM**：补齐 `armeabi-v7a`。先确认 ATV 镜像是否带 32 位翻译库（`/system/lib/libndk_translation.so` 和 arm linker）。
3. **重负载实测**：glmark2 太轻；换真实 3D 游戏或 GFXBench，看性能和稳定性，同时盯 Xid。
4. **界面微调**：隐藏状态栏、smartdock 之类，用 KernelSU 模块或 `waydroid prop`，不改镜像。
5. **Widevine**：vendor 带 `drm-service.widevine`，级别未实测，推测 L3（Netflix 之类只有标清），无法提升。
6. **跟进上游**：ATV 出新 system 镜像、waydroid-nvidia 出 rc11 时 rebase 重编（`scripts/apply-nvidia.sh`、`scripts/build.sh`、`scripts/reinstall-vendor.sh`）。

## 卡片模式与输入法的已知问题

1. **缩放时内容滞后**：拖动 KDE 窗口边框时窗口先变，Android 要等 `cmd` 调整任务尺寸、应用重新排版后才跟上。可试：拖动期间先按比例缩放旧画面占位，或合并多次 resize。
2. **卡片共用一块 Android 屏幕**：显示尺寸 = 宿主 + 200 headroom，窗口多时可能互相遮挡点击区域；卡片和桌面窗口只能二选一。根治需要每个窗口一个虚拟显示，改动大。
3. **重新打开的卡片位置由 KWin 决定**：Wayland 客户端不能指定位置。可试：KWin 窗口规则按 app_id（`waydroid.<包名>`）记住位置，或 KWin 脚本。
4. **内嵌预编辑不显示**：fcitx5 用 Ctrl+Alt+P 打开内嵌预编辑后，Android 输入框里仍看不到预编辑，原因未查。（默认 `PreeditEnabledByDefault=False` 时预编辑显示在候选框里，与宿主应用一致。）
5. **输入法桥未测场景**：密码框（content purpose 已传给宿主）、多行文本里的 Enter、`delete_surrounding_text`（fcitx5 部分联想功能会用）。

## 维护备忘

- 重装用 `scripts/reinstall-vendor.sh`，它会把 `debug.hwui.renderer` 写回 `skiavk`。
- 清空 Waydroid data 后要重新放 `/data/adb/ksud`、装管理器（`kernelsu/README.md` 第 5 步），并重新 `waydroid prop set persist.waydroid.multi_windows true`。
- `nvidia/waydroid-nvidia` 中 `eec39aa` 及之前的提交不能重写：native bundle 的 BUILD-RECORD 记着从 `eec39aa` 编出，`install.sh --source` 要求本地源码是它的后代。
- 调试：`setprop waydroid.dump_hal 1`（下一帧打印图层、任务、窗口）；`waydroid prop set persist.waydroid.clipboard_debug true` 后重启会话（logcat `hwcomposer` 的 `clipboard:` 行）。
