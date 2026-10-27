---
name: waydroid-a17-test
description: Test this project's Waydroid Android 17 NVIDIA stack on the author's machine — restart the session, run commands in the guest, try a module through the vendor overlay, NVDEC/NVENC Codec2 regression, Chrome WebCodecs/WebRTC hardware-encode check, graphics/HWUI checks and screenshots of Android windows. Use whenever a change must be verified inside Waydroid, for "测一下", "回归", "进容器", "logcat", "overlay", "截图" or any guest-side debugging.
---

# 测试

机器：RTX 4060 Laptop、nvidia-open 615.78.08、KDE Plasma Wayland。NVIDIA 渲染节点 `/dev/dri/renderD129`（`renderD128` 是 AMD 核显）。
脚本在 `.agents/skills/waydroid-a17-test/scripts/`（下文 `$T`）。需要 sudo 的脚本读 `SUDO_ASKPASS`。

## 会话与容器

```bash
$T/session-restart.sh                 # 后台启动并等到 ready；前台 `waydroid session start` 不会返回
$T/guest.sh 'logcat -d -s nvc2 nvc2-enc | tail'   # root shell 进容器
```

- 容器 `/data` = 宿主 `~/.local/share/waydroid/data`，推文件直接拷到 `.../data/local/tmp`。
- 应用：`waydroid app launch <包名>`；网页：`waydroid app intent android.intent.action.VIEW <url>`。
- 图形确认：`$T/guest.sh 'dumpsys SurfaceFlinger | grep GLES:'` 应是 ANGLE → NVK（RTX 4060）。
- `dmesg | grep -i xid` 不应有新的 NVIDIA Xid。

## overlay 试单个模块

`sudo install` 到 `/var/lib/waydroid/overlay/vendor/<同 vendor 内路径>`，再 `session-restart.sh`。`/vendor/odm` 下的
服务同理（`overlay/vendor/odm/bin/hw/`，组 2000，0755）。测完记录 overlay 里有什么：发版前要全部删掉
（`sudo find /var/lib/waydroid/overlay/vendor -type f`）。`media_codecs_c2.xml` 不在 overlay：它由宿主
`/var/lib/waydroid-nvidia/vendor-image/` 只读挂进去，改编码器列表要同时改那里的 XML 和 `install.json` 里的
`media.xml_sha256`/`codecs`，否则服务启动校验失败。

## 编解码回归

```bash
make -C "$WS/nvidia/waydroid-nvidia/nvidia-prolapse/media" c2-smoke c2-enc-smoke   # 首次
CODEC_SMOKE_OUT=/tmp/codec-evidence $T/codec-smoke.sh
```

期望：四种解码各 60 帧、0 bad buffers；三种编码各 60 进 60 出，宿主 FFmpeg 解码 0 错误（H.264 为 Constrained Baseline）。
编码器开关 `persist.waydroid.nvidia_video_encode`、解码器开关 `persist.waydroid.nvidia_video_decode`（`waydroid prop set`）。
脚本按组件名创建解码器，保留每个客户端及 FFmpeg/ffprobe 退出码，严格要求四解码各 60 帧/0 坏缓冲、三编码各 60 入/60 出、宿主 ffprobe 各 60 帧且 FFmpeg 无错误。另跑运行中 flush 后完整重播、有未完成工作时销毁、128 字节 0xff 坏码流输入（须零图像，收到 EOS 或明确错误）。反向门禁：`CODEC_SMOKE_FAULT=client-failure|wrong-name|truncated|bad-buffer`（逐一运行，均应非零；bad-buffer 为客户端首张图像的空缓冲故障注入）。输出目录保留原始日志与退出码。宿主 C 编码计时用 `M/test/enc-benchmark.py OUT`，330 帧去前 30、五次交替顺序，生成逐帧 CSV 与统计 JSON。

### Surface 与 seccomp 窗口

```bash
$T/surface-smoke.sh "$WS/reports/codec2-rust/phase0/surface/run"
CODEC_SMOKE_OUT="$WS/reports/codec2-rust/phase0/seccomp/run/clients" \
  $T/seccomp-check.sh "$WS/reports/codec2-rust/phase0/seccomp/run" \
  "$WS/nvidia/waydroid-nvidia/nvidia-prolapse/media/odm/etc/seccomp_policy/android.hardware.media.c2@1.2-nvprolapse.policy"
```

Surface 脚本编译 `c2_surface_smoke`，四个指定组件各断言 60 输入、60 输出、60 张 PRIVATE Image、EOS 和正常销毁；每个退出码保存在 `exit-codes.tsv`。
seccomp 脚本第二参数可留空（使用当前策略），其后可传自定义稳态负载命令，默认跑 `codec-smoke.sh`。冷窗口由 init `ctl.sigstop_on` 在 exec 前暂停，attach 后恢复并等待 Store；稳态窗口 attach 后跑客户端。以成功的非 NULL `PR_SET_SECCOMP` 为界，递归展开实际 guest include，保存安装前后 syscall 集合、逐调用实参及覆盖结论；未覆盖、未知参数谓词或 SIGSYS 均失败，不能用“无 SIGSYS”替代策略对照。
提供策略文件时仅临时只读 bind 该文件，核对部署 SHA256，EXIT 时关闭 sigstop、停止服务、卸自身 bind、重启服务并核对原 SHA256。两个脚本共用 `/tmp/wd-guest.lock`；持锁上层用 `WD_GUEST_LOCKED=1` 调用，避免嵌套锁。

## Chrome 硬件编码

```bash
WEB_ENCODE_OUT=/tmp/web-evidence $T/web-encode-test.sh 150
```

仅在 guest Chrome 中打开页面。每个用例有 run UUID 与独立 ID；页面开始前 POST 请求宿主清空 logcat 并等待确认，结束后 POST JSON，宿主立即归档该窗口日志。WebCodecs 四项严格要求 60 输出、有关键帧、无错误；WebRTC 三项要求编码帧数 > 0、宽高至少 960×540，且各自窗口内有对应 AVC/HEVC/AV1 组件打开日志。证据目录含每项 JSON、logcat、开窗时间和总退出状态；超时、缺项或任一断言失败均非零。

## 截图与桌面

- 用 `kde_window` 的 list/activate/place 找和摆窗口，再截全屏；多窗口模式下每个安卓应用一个 KDE 窗口，
  标题 `waydroid.<包名>`。整块安卓桌面窗口叫 `Waydroid`。
- 截图要公开时先看内容：YouTube 推荐栏、通知、账号头像都可能带不该公开的东西，裁掉或换画面。

## 宿主 Chrome/Firefox

启动前清掉驱动变量：`env -u LIBVA_DRIVERS_PATH -u LIBVA_DRIVER_NAME -u NVD_BACKEND -u NVD_LOG`；实验用临时 profile
（`--user-data-dir=/tmp/...`），用完删除。

## 调试开关

`setprop waydroid.dump_hal 1`（下一帧打印图层、任务、窗口）；`waydroid prop set persist.waydroid.clipboard_debug true`
后重启会话（logcat `hwcomposer` 的 `clipboard:` 行）。清空 Waydroid data 后要重新放 `/data/adb/ksud`、装 KernelSU 管理器
（`kernelsu/README.md` 第 5 步），并重新 `waydroid prop set persist.waydroid.multi_windows true`。
