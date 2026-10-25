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
$T/codec-smoke.sh
```

期望：四种解码各 60 帧、0 bad buffers；三种编码各 60 进 60 出，宿主 FFmpeg 解码 0 错误（H.264 为 Constrained Baseline）。
编码器开关 `persist.waydroid.nvidia_video_encode`、解码器开关 `persist.waydroid.nvidia_video_decode`（`waydroid prop set`）。

## Chrome 硬件编码

```bash
$T/web-encode-test.sh       # 打开 scripts/web/index.html，约 45 秒后打印服务端打开的编码器
```

结果显示在页面上，截 Chrome 窗口读取。`chrome://gpu` 的 Video Encode 应为 Hardware accelerated。
WebRTC 分辨率由带宽估计决定，8 秒内停在 960×540 不算失败；`nvc2-enc` 没有日志行才是走了软件编码。

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
