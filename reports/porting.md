# waydroid-nvidia (nvidia-prolapse) 移植到 Android 17 报告

## 结果

| 项目 | 状态 | 证据 |
|---|---|---|
| 系统镜像 | WayDroid-ATV LineageOS 24.0（Android 17，SDK 37）原版 | `ro.build.version.release=17` |
| vendor 镜像 | 自编 `lineage_nvidia_waydroid_x86_64-cp2a-userdebug`，`ro.vendor.nvidia_prolapse.version=v0.2.0-rc10-a17-multiqueue` | `src/out/target/product/waydroid_nvidia_x86_64/vendor.img` |
| native bundle | rc10 Rust RM/HAL/nvrm 原样，NVK 重编为双图形队列（`nvidia/build/native-multiqueue`，BUILD-RECORD sha256 `684a32a5…`） | `reports/nvk-multiqueue.md` |
| 发布门禁 | PASS：22 个用例 + media，内核模块 615.78.08 | `logs/nvidia-setup-6.log` |
| 启动 | `sys.boot_completed=1`，crash 缓冲区 0 次 abort | `logcat -b crash` |
| GLES | ANGLE → NVK → RTX 4060 Laptop | `ANGLE (NVIDIA, Vulkan 1.4.354 (NVIDIA GeForce RTX 4060 Laptop GPU (NVK NV197)), NVK-26.0.128.5), OpenGL ES 3.2` |
| HWUI | `skiavk`（`Pipeline=Skia (Vulkan)`） | `dumpsys gfxinfo` |
| gralloc | `minigbm_gbm_mesa`，`/dev/dri/renderD129`（NVIDIA） | `getprop ro.hardware.gralloc` |
| 视频硬解 | H.264 / HEVC / VP9 / AV1 1080p60 均由 `c2.nvprolapse.*`（NVDEC）解码，画面正常 | Just Player + logcat |
| Xid | 全程 0 条 `NVRM: Xid`（含两轮 glmark2 和 HWUI 基准） | `dmesg` |
| binder | `/dev/binder`、`hwbinder`、`vndbinder` 可用 | `service list` |
| KernelSU | 本地签名管理器 32708 显示 Working（LKM），无更新提示；Termux 授权后 `su -c id` 得到 `uid=0(root)`，撤销授权后拒绝 | `reports/ksu-manager-local.png` |

## 改动所在位置

| 仓库 | 分支 | 内容 |
|---|---|---|
| `src/hardware/waydroid` | `nvidia-a17` | hwcomposer 移植 18 个提交和 `%llx` 格式修正（`hwcomposer.md`）；`f676385` show-full-ui 静止画面不出窗口；`a122fa3` A17 图层按任务事件映射到任务；`04d1d60` 多窗口 freeform 卡片模式；`379ec63` 多窗口下的 Android 桌面窗口；`17c36f7` 宿主输入法直通（`hostime/`、`hwcomposer/ime-bridge.*`） |
| `src/external/minigbm` | `nvidia-a17` | gbm_mesa 移植 7 个提交；`cros_gralloc_handle.usage` 恢复为 `int32_t`（`minigbm.md`） |
| `src/hardware/interfaces` | `nvidia-a17` | composer 2.1/2.4 重连修正（`composer-hal.md`） |
| `src/external/wayland-protocols` | `nvidia-a17` | 协议版本提升到 1.49 |
| `src/device/waydroid/waydroid` | `local-build` | x86_64 不编 Mesa nouveau Vulkan；`5421c32` 预装 `WaydroidHostIme` |
| `src/vendor/waydroid/init` | `nvidia-a17` | `597f6e5` 识别 nvidia-prolapse；`75b2978` 视频解码交给 NVDEC |
| `nvidia/waydroid-nvidia` | `a17-local` | 门禁 EROFS/APEX/VNDK 支持、KernelSU seccomp 补丁、双队列 NVK（`eec39aa`）、本地安装器（`db78568`、`e63b1fb`）；安装器不重写已有目录、只在图标变化时刷新图标缓存（`26fdaa4`、`b1a3597`、`a30d79a`） |
| `nvidia/product` | （主分支） | `libhwminijail`；native bundle pin（`de9e574`） |
| `ksu/KernelSU` | `local-manager` | 管理器源码（b42ad459），本地 keystore 签名 |

`nvidia/work/` 中的独立克隆与 `hardware/waydroid`、`external/minigbm` 同步，`scripts/apply-nvidia.sh` 从这些克隆 cherry-pick；`vendor/waydroid/init` 的两个提交只在 `src/` 树里。

## 日常操作

- 重编并重装：`scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug vendorimage`，然后 `scripts/reinstall-vendor.sh`。后者打包 vendor，调用 `scripts/install-waydroid-nvidia.sh` 从本地 `a17-local` 源码安装全套（native bundle 取自 product pin，vendor 取自 `out-ota/`，seccomp 和门禁改动一并保留），最后运行 `waydroid-nvidia-setup`。
- 只改 hwcomposer 时：`scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug hwcomposer.waydroid`（约 1.5 分钟），`waydroid session stop`，把 `src/out/target/product/waydroid_nvidia_x86_64/vendor/lib64/hw/hwcomposer.waydroid.so` 复制到 `/var/lib/waydroid/overlay/vendor/lib64/hw/`，再启动会话（约 20 秒）。overlay 里的库优先于 vendor 镜像；装新 vendor 镜像前要删掉它，否则仍用旧库。
- 只想核对安装内容：`bash scripts/install-waydroid-nvidia.sh --destdir /tmp/stage`（无需 sudo）。
- 基准：`scripts/bench-hwui.sh LABEL`，汇总 `scripts/bench-summary.py LABEL...`。

## A17 上的问题和处理

1. **`gralloc-mapper is missing`（composer 和 SurfaceFlinger 中止）。** ATV 的 C++ `waydroid-init` 驱动表里没有 nvidia，回退到没有 mapper 的 `gralloc=default`。vendor 带 `vulkan.nvidia.so` 时改用 `minigbm_gbm_mesa` + `vulkan.nvidia`，`ro.hardware.egl` 保留主机写入的值。
2. **SurfaceFlinger `Failed to create a valid texture`。** ATV 的 A17 minigbm 把句柄 `usage` 加宽为 `int64_t`，句柄变成 36 个 int，预编译 HAL 要求 35 个。恢复为 `int32_t`；句柄中的 usage 只用于低位软件读写掩码判断。
3. **HWUI 断言 `queueCount < kRequestedQueueCount`。** A17 HWUI 在图形队列族上创建 2 个队列：RenderThread 用第一个，`HardwareBitmapUploader` 的上传线程用第二个，两者并发提交。NVK 原本只报 1 个。补丁 `nvk-rm-graphics-multiqueue.patch` 把图形族改为 2 个队列；每个 VkQueue 已有独立的 RM context/TSG/channel/GPFIFO，Rust 后端无需改动。双线程 512 次提交的 probe 在 x86_64 和 i686 上都通过。
4. **KernelSU `ksud` 收到 SIGSYS。** Waydroid 的 LXC seccomp 杀掉所有 `reboot(2)`，KernelSU 通过 `reboot(0xDEADBEEF, …)` 分发驱动 fd。改为 `reboot kill [0,3735928559,SCMP_CMP_NE]`，其余 reboot 仍被终止。
5. **视频播放失败（`c2.ffmpeg.*.decoder died`）。** ATV 把 `c2.ffmpeg` 视频 rank 设为 0，排在 NVDEC 服务 `c2.nvprolapse`（0x10）之前；`c2.ffmpeg` 的 DRM hwaccel 在 NVIDIA 栈上初始化时调用 `eventfd`，被 ffmpeg 服务的 seccomp 终止。nvidia-prolapse 下把 `c2.ffmpeg` 视频 rank 设为 32 并关闭其 DRM hwaccel，它退为 NVDEC 之后的软解。
6. **构建环境。** Mesa nouveau 的 Rust 部分在离线容器里找不到 i686 rustc，去掉了 nouveau（NVIDIA 用自己的 NVK）；容器里补了 `ld.lld` 符号链接；hwcomposer 的 `-Wformat` 错误。
7. **多窗口（`persist.waydroid.multi_windows=true`）。** A17 的 `TID:` 前缀落在没有 buffer 的 surface 上，应用画面在 `VRI-<pkg>/<activity>` 子图层里，hwcomposer 改为按 WMS 任务事件把它们映射到任务。system 镜像里的 task 服务事务号是旧的（`setFocusedTask` 实际变成 `removeTask`，点窗口就关应用），hwcomposer 改为直接执行 `cmd activity`/`cmd window`。窗口模型改为 freeform：Android 显示尺寸固定，每个任务以 freeform 窗口进入 WMShell 的 desk，在 KDE 中各占一个顶层窗口，只显示任务的内容区（Android 自带标题栏被裁掉）。KDE 负责标题栏、拖动和缩放，缩放时同步调整任务边界；切换窗口无需重连显示。desktop 模式的圆角会强制 CLIENT 合成、导致卡片透明，freeform 下关闭。

## KernelSU

- 内核模块：`kernelsu-dkms 3.3.1+28+gb42ad459-2`。`~/.cache/yay/kernelsu-dkms/PKGBUILD` 的 pkgrel 2 把 `KSU_EXPECTED_SIZE=0x02ec`、`KSU_EXPECTED_HASH=d77ee93d…` 写入 dkms 的 MAKE，内核因此认本地签名的管理器，官方管理器不再被认。以后升级 kernelsu-dkms 要保留这两个变量（取值在 `ksu/out/expected.txt`）。
- 管理器：`ksu/out/KernelSU_v3.3.1-28-gb42ad459_32708-local.apk`，keystore 在 `ksu/keystore/`（权限 600，密码在同目录 README）。构建说明见 `ksu-manager-build.md`。
- 开机加载：`/etc/systemd/system/kernelsu-load.service`（源文件 `host/kernelsu-load.service`），在 `waydroid-container` 之前运行 `load-kernelsu`，模块已加载时跳过。容器启动时 init 自动执行 `ksud post-fs-data` / `services` / `boot-completed`。

## 多窗口

开启：`waydroid prop set persist.waydroid.multi_windows true`，重启会话后用 `waydroid app launch <包名>` 打开应用，每个应用一个 KDE 窗口。

开始菜单的「Waydroid」（`waydroid show-full-ui`）打开完整的 Android 桌面，放在带 KDE 标题栏的普通窗口里，可拖动、缩放、最大化，Android 显示跟着窗口大小变。桌面打开时所有应用都在桌面里，用 Android 自己的窗口标题栏；这时从主机单独打开应用，也会进桌面并把桌面提到前面。关闭桌面不会结束应用，它们各自回到原来的 KDE 窗口，大小恢复为打开桌面前的值。两种状态不同时存在：所有应用共用一块 Android 屏幕，单独的窗口在桌面里虽然看不见，仍占着屏幕位置，会截走点击。

已在桌面上实测（build-22）：计算器和时钟并排，两个窗口交替点击都落在正确位置；键盘输入；拖动标题栏移动；KDE 缩放后应用按新尺寸重排；长按出现的复制/粘贴浮动工具栏正常显示，且不会让窗口跳位；剪贴板双向互通（Android 复制 → `wl-paste`，`wl-copy` → Android 粘贴）；点关闭按钮后窗口和 Android 任务一起移除；dmesg 无 Xid。

剪贴板服务由主机上的 waydroid 用 `/usr/bin/python3` 加载 `python-pyclip`；PATH 里若有 linuxbrew 等其他 python3，命令行测试时要用 `/usr/bin/python3`。

## 宿主输入法

宿主的输入法（KDE 设置里「虚拟键盘」选的那个，本机是 Fcitx 5；ibus 同理）可以直接在 Android 应用里打字，卡片窗口和桌面窗口都可用。在 Android 输入框里按 Ctrl+Space 切换中英文，和宿主应用一样，候选框贴在 Android 输入框的光标旁边。

实现分两半：
- hwcomposer 在 Wayland 控制连接上绑定 `zwp_text_input_v3`，Android 输入框获得焦点时启用，把光标位置（换算到所在窗口的坐标）交给宿主；宿主输入法没吃掉的按键照旧走 `wl_keyboard`。
- vendor 应用 `WaydroidHostIme`（`id.waydro.hostime`，`/vendor/app`）是一个没有界面的 Android 输入法，把上屏、预编辑、删除写进输入框，并上报光标位置。
- 两者之间是抽象 unix socket `@waydroid-hostime`，hwcomposer 只接受该包 uid 的连接。协议写在 `hwcomposer/ime-bridge.h`。
- 开机时 vendor init（`/vendor/etc/init/waydroid-hostime.rc`）以 shell 身份运行 `/vendor/bin/waydroid-hostime-enable`，启用并设为默认输入法；用户若已经选了原生键盘以外的输入法则不改默认。用 shell 是因为 A17 的 `cmd input_method ime` 只接受 shell/root，`cmd settings put` 在 system uid 下会触发框架 NPE。

已实测：双拼输入中文上屏、数字选词、退格、切回英文、Ctrl+A/C，候选框随光标移动；桌面窗口内同样正常；开机后自动启用并连上 hwcomposer；dmesg 无 Xid。预编辑是否内嵌在输入框里由宿主输入法决定，本机 fcitx5 配置 `PreeditEnabledByDefault=False`，预编辑显示在候选框里，宿主原生应用（KWrite）也是如此。

## 性能：skiavk 与 skiagl

同一 vendor、同一会话条件下，各跑 3 轮。滚动测试：Settings「所有应用」列表上下各 15 次快速滑动，用 framestats 逐帧统计（每种 10800 帧）。冷启动取 3 次中位数。

| 指标 | skiavk | skiagl |
|---|---|---|
| 整帧耗时 mean / p50 / p90 / p99 ms | 1.55 / 1.42 / 2.10 / 3.05 | 1.72 / 1.59 / 2.27 / 3.14 |
| RenderThread mean / p50 / p90 / p99 ms | 1.28 / 1.16 / 1.69 / 2.70 | 1.45 / 1.36 / 1.88 / 2.79 |
| swap 后 GPU mean / p50 / p90 / p99 ms | 0.61 / 0.51 / 0.98 / 1.96 | 0.71 / 0.63 / 1.01 / 1.97 |
| 卡顿帧 | 0.01% | 0.01% |
| 冷启动 Calculator ms | 167 | 184 |
| 冷启动 DeskClock ms | 156 | 184 |
| 冷启动 Jelly 浏览器 ms | 288 | 219 |
| 冷启动 KernelSU 管理器 ms | 591 | 611 |
| 冷启动 Just Player ms | 161 | 167 |
| glmark2 2023.01 分数 | 6499 | 6605 |

- 界面渲染：skiavk 整帧和 RenderThread 都快约 10%，两者都远低于 16.7 ms，没有可感知的卡顿。
- glmark2 本身走 GLES（ANGLE → NVK），不经过 HWUI，两次分数差 1.6%，属于正常波动；它衡量的是 GLES 路径，不反映两种 HWUI 模式的差别。
- 冷启动：除 Jelly 外 skiavk 略快；Jelly 反过来快 70 ms，可能与 WebView 初始化有关，未深究。
- 当前保持 `skiavk`（项目默认，`waydroid-nvidia-setup` 也会写这个值）。

## 已知限制

- glmark2 的 64 位版在自身 `Log::info` 中复用已消耗的 `va_list` 而崩溃（glmark2 的 bug，与本栈无关），测试改用 32 位版（`pm install --abi x86`）。
- SetupWizard 仍停在首屏：ATV 跳过蓝牙配对的补丁与源码冲突未打上，首次打开时手动走完即可。
- 安装来源证明未验证：本地没有 cosign 和签名包，安装器只做了 SHA256 和 BUILD-RECORD 校验。
