# Waydroid A17 + NVIDIA：待选改进清单

当前状态和报告见 `reports/porting.md`。

## 现状（2026-10-24 实测）

- ABI 列表：`x86_64, arm64-v8a, x86`；ARM 翻译用 ATV 自带的 `/system/lib64/libndk_translation.so`，没有 libhoudini，也没有 `armeabi-v7a`。
- 没有 GApps 或 microG（ATV VANILLA 版 system 镜像）。
- vendor 带 `android.hardware.drm-service.widevine` 和 clearkey；Widevine 级别未实测，推测为 L3。
- `persist.waydroid.multi_windows=true`：每个应用一个 KDE 窗口（freeform 卡片），`show-full-ui` 打开带 KDE 边框的 Android 桌面窗口。
- 宿主输入法直通已完成（`17c36f7`、`5421c32`）：fcitx5 经 text-input-v3 在 Android 里上屏，候选框跟随光标。
- root：KernelSU（本地签名的管理器 32708，`kernelsu-load.service` 开机加载），Termux 已授权。

## waydroid_script（casualsnek）各功能对照

这个脚本只支持 A11/A13，靠往 system 镜像里塞文件实现，在我们的 A17 环境上不能直接用。

| waydroid_script 的功能 | 我们现在 | 结论 |
|---|---|---|
| ARM 翻译 | ATV 自带 `libndk_translation`，ABI 为 `x86_64, arm64-v8a, x86` | 64 位 ARM 应用能跑；缺 `armeabi-v7a`，只有 32 位 ARM 库的老应用/游戏装不上。值得做 |
| Magisk | 已用 KernelSU 替代，root 和授权已验证 | 不需要 |
| Widevine | vendor 中有 `drm-service.widevine` | 推测为 L3（软件级），Netflix 之类只能标清，这里无法提升；未实测 |
| GApps / microG | 无（VANILLA） | 想用 Play 或依赖 GMS 的应用需要选一条路：microG（轻量开源，用 KernelSU 模块做签名伪装）；换 ATV GAPPS 版 system 镜像（最省事，Play 认证需手动登记设备 ID）；只装 Aurora Store、不要 GMS |
| 隐藏状态栏、smartdock 等界面调整 | 未做 | 用 KernelSU 模块或 `waydroid prop` 实现，不改镜像 |

## 与本环境直接相关的改进

1. **多窗口模式**：已完成。`04d1d60` freeform 卡片模式，`379ec63` 带 KDE 边框的桌面窗口。
2. **剪贴板与文件共享**：剪贴板已改用 ext-data-control（`2fba6a7`），主机复制经输入法推送进 Android，Python 服务已删除；文件共享（把 `~/Downloads` 等目录挂到安卓存储）未做。
3. **32 位 ARM 支持**：在 ndk_translation 上补齐 `armeabi-v7a`。先确认 ATV 镜像是否带 32 位翻译库（`/system/lib/libndk_translation.so` 以及 arm 的 linker 等）。
4. **重负载游戏和基准**：glmark2 负载太轻，换真实 3D 游戏或 GFXBench，看 4060 在这套栈上的实际性能和稳定性（同时盯 Xid）。
5. **跟进上游**：ATV 出新 system 镜像、waydroid-nvidia 出 rc11 时，用现有脚本 rebase 后重编（`scripts/apply-nvidia.sh`、`scripts/build.sh`、`scripts/reinstall-vendor.sh`）。

## 卡片模式与输入法的已知小问题（以后迭代）

1. **缩放时内容滞后**：拖动 KDE 窗口边框时窗口先变，Android 要等 `cmd` 调整任务尺寸、应用重新排版后才跟上，快速拖动能看到内容慢一拍。可试：拖动期间先按比例缩放旧画面占位，或节流后合并多次 resize。
2. **卡片挤在同一块 Android 屏幕上**：显示尺寸 = 宿主 + 200 headroom，窗口多时可能重叠、互相遮挡点击区域；卡片和桌面窗口只能二选一。根治需要每个窗口一个虚拟显示，改动大。
3. **恢复的卡片位置由 KWin 决定**：Wayland 客户端不能指定位置，重新打开的卡片不一定回到原处。可试：KWin 窗口规则按 app_id（`waydroid.<包名>`）记住位置，或写 KWin 脚本。
4. **Android 输入框里的内嵌预编辑没验证**：本机 fcitx5 `PreeditEnabledByDefault=False`，预编辑显示在候选框里（与 KWrite 一致）；用 Ctrl+Alt+P 打开内嵌预编辑后 Android 输入框仍未显示，原因未查。
5. **输入法桥未覆盖的场景**：密码框（content purpose 已传给宿主）、多行文本里的 Enter、`delete_surrounding_text`（fcitx5 的部分联想功能会用）均未实测。
6. **卡片偶尔整窗透明**：一次重启会话后 `waydroid app launch` 打开的浏览器卡片，KDE 窗口在、hwcomposer 显示 `window shown=1`、图层正常，但窗口里什么都不画；调整窗口尺寸也不恢复，force-stop 后重开正常。只出现一次，未复现，原因未查。

GApps：已换 ATV 的 GAPPS 版 system 镜像，Play 商店已认证。

## 操作注意

- 重装用 `scripts/reinstall-vendor.sh`。它会把 `debug.hwui.renderer` 写回 `skiavk`，当前就是这个值。
