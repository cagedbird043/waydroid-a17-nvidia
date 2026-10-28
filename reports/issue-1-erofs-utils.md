# Issue #1：门禁 EROFS 工具依赖

## 核实

- 问题全文由 `gh issue view 1 -R cagedbird043/waydroid-a17-nvidia` 获取：门禁因找不到 `dump.erofs` 回滚。
- 确切调用：工作区 `nvidia/waydroid-nvidia/packaging/native/release_gate.py:202-209` 的 `_dump_raw()`，EROFS 分支第 206 行执行 `dump.erofs --path=… --cat`；第 266 行还执行 `dump.erofs --path=… --ls`。实际镜像可能是 EROFS system.img；函数同时处理系统运行时提取，不能从错误文本断言缺失工具读取的是 vendor.img。
- 安装来源：`aur/waydroid-a17-nvidia-bin/PKGBUILD:46-47` 下载固定上游源码与发布 tag 源码；`:118-123` 将 tag 内 `patches/waydroid-nvidia/*.patch` 应用到上游源码；`:175-178` 的 `package()` 调用该已补丁源码里的 `install-native.sh`，传入源码树和 native tarball。
- 工作区 `nvidia/waydroid-nvidia/packaging/native/install-native.sh:32-47` 将源码树内 `packaging/native/release_gate.py`、`vendor_image.py` 等复制到 `/usr/lib/waydroid-nvidia/native/`；`:53-55` 单独把 native tarball 解压到 `native/release/`。因此 Python 门禁由 AUR 的固定上游源码 + publish tag 补丁安装；native bundle 提供二进制 payload、gate 测试程序与数据，不是此 Python 门禁脚本来源。

## 外部命令审计

以下范围是本包实际使用的 vendor-image release gate（`vendor_image.py:268` 调用 `release_gate.run(..., vendor_image=new)`），不是开发者源码构建门禁。

|命令|Arch 包/来源|证据|依赖状态|
|---|---|---|---|
|`dump.erofs`|`erofs-utils`|`release_gate.py:206,266`|本次新增|
|`debugfs`|`e2fsprogs`|`release_gate.py:209`；`waydroid/nvidia_native.py:1058`|原已声明|
|`unshare`|`util-linux`|`release_gate.py:360`，32 位测试 PID namespace|原已声明|
|`python3`|`python`|`release_gate.py:450,558`|原已声明|
|`readelf`|`binutils`|`nvidia-prolapse/media/tools/check-xmlgen-elf.py:14`（从 `release_gate.py:450` 调用）|原已声明|
|`nm`|`binutils`|`release_gate.py:578`|原已声明|
|`linker` / `linker64`|用户 Android system.img|`release_gate.py:349,355-357`|不是宿主 Arch 包依赖|
|`vk-compute`, `vk-graphics`, `vk-interop`, `anb-roundtrip`, `astc-roundtrip`, `etc2-roundtrip`, `gl-triangle`, `gl-dmabuf`, `gl-skia-shaders`, `gl-yuv`, `nvc2-xmlgen`|native bundle 的 `gate/bin/<ABI>/`|`release_gate.py:419-445,532-533`|随包资产安装|

该生产门禁路径没有发现其他缺失的宿主工具依赖。`release_gate.py:482,494` 的 bash/stage-odm 和 make/smoke 属于不传 vendor_image 的开发门禁路径，不是本次 AUR setup 执行路径。setup 激活/回滚所需的 `systemctl` 来自 Arch 基础系统的 systemd；`waydroid` 为本包自身（`vendor_image.py:357,360,380-381`）。

## 修复

- `pkgver` 保持 `20261028.2`，`pkgrel=2`。
- `depends` 增加 `erofs-utils`，重新生成 `.SRCINFO`；资产 digest 与 tag 不变。
- `TODO.md` 记录下个版本在门禁开始前检查所需工具并明确提示 Arch 包名。

## 验证

- 干净 `archlinux:latest` 容器中，安装前 `command -v dump.erofs` 返回 1；独立的第二个干净容器同样返回 1。
- `pacman -Sy` 后直接 `source /pkg/PKGBUILD`，用 `pacman -S --needed --noconfirm "${depends[@]}"` 安装全部运行依赖成功；`pacman -Q erofs-utils` 为 `1.9.4-1`，`dump.erofs --help` 成功。`pacman -Qo` 确认上述工具的包归属。
- 工作区日志：`logs/issue-1-arch-dependencies.log`、`logs/issue-1-arch-without-erofs.log`。默认镜像服务器遇 TLS EOF，TUNA 遇 403；最终干净容器使用 USTC/阿里镜像完成安装，不改宿主 pacman 配置。
- 本次只验证依赖安装与工具执行，不运行需要 GPU 的完整 release gate；未改动镜像、native bundle、release tag 或资产校验和。
- `/tmp/codec2-inv-*` 已删除，glob 确认无残留。
