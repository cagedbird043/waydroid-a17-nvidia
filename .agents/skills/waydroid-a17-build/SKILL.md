---
name: waydroid-a17-build
description: Build this project's Waydroid Android 17 NVIDIA vendor image and its pieces — single vendor modules (hwcomposer, gralloc, Codec2 service), the Rust RM backend / NVK / nvrm native stack, the native bundle and its pin, the full two-pass vendorimage — and keep publish/patches in sync with the source repositories. Use for any compile, rebuild, bundle, stage-product, Soong, "编译", "重编", "打补丁" or patch-export task in this repository.
---

# 构建

## 工作区

本仓库（publish）是工作区 `~/Projects/waydroid-a17` 的子目录，源码和产物都在工作区里，不进本仓库。脚本用
`$WAYDROID_A17_WS`，缺省取本仓库的上一级。

| 工作区路径 | 是什么 | 本仓库里的对应 |
|---|---|---|
| `src/` | LineageOS 24.0 + WayDroid-ATV 树（repo） | `patches/<仓库>/` |
| `src/hardware/waydroid` 等 | 分支 `nvidia-a17`（device 树是 `local-build`） | `patches/hardware_waydroid/` … |
| `nvidia/waydroid-nvidia` | 分支 `a17-local`：Rust RM、NVK、nvrm、Codec2 媒体源码、Waydroid 主机补丁 | `patches/waydroid-nvidia/` |
| `nvidia/product` | `vendor/nvidia-prolapse` product 层（git，main） | `nvidia-product/`（rsync 镜像） |
| `nvidia/build/native-*` | native bundle（BUILD-RECORD.json + payload） | Release 资产 |
| `scripts/` | build.sh、stage-product.sh 等 | `scripts/`（同内容副本，从工作区运行） |

补丁基线和数量见 [references/patch-bases.md](references/patch-bases.md)。

## 单个模块（快速迭代）

```bash
cd "$WS" && scripts/stage-product.sh      # 改了 nvidia/product 或媒体源码后
scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug <模块>   # 如 hwcomposer.waydroid
```

产物在 `src/out/target/product/waydroid_nvidia_x86_64/vendor/`，放进 `/var/lib/waydroid/overlay/vendor/` 的同名路径，
再重启会话（`waydroid-a17-test` skill）。overlay 优先于 vendor 镜像，发版前必须清空。

Codec2 服务模块名 `android.hardware.media.c2@1.2-service-nvprolapse`，源码由 stage-product.sh 从
`nvidia/waydroid-nvidia/nvidia-prolapse/media/{core,c2}` 放进 `src/vendor/nvidia-prolapse/media-src/`。
宿主单测：`make -C nvidia/waydroid-nvidia/nvidia-prolapse/media test`；真 GPU：`make realtest-all`、`make realenc`。

## native 栈（改了 driver-source/ 之后）

先在 `nvidia/waydroid-nvidia` 提交，再：

```bash
S=.agents/skills/waydroid-a17-build/scripts      # 在本仓库根目录运行
$S/rebuild-native.sh            # Rust RM → NVK → nvrm（32/64 位）→ nvc2-xmlgen，约 2 分钟
$S/rebuild-native.sh --rust-only   # 只编 Rust 库，测试用，不能发版
```

`nvc2-xmlgen` 是 RM crate 的 `xmlgen-cli` 非默认 feature bin，仅动态调用 RM C ABI。
RM 先编好，再用 Make 的 Cargo 适配目标（每次由 Cargo 判断增量）：

```bash
make -C "$WS/nvidia/waydroid-nvidia/nvidia-prolapse/media" xmlgen \
  RUST_PROFILE=release CARGO_TARGET_DIR="$WS/nvidia/waydroid-nvidia/build/nv-rm-rust" \
  NV_C2_RM_LIB_DIR="$WS/nvidia/waydroid-nvidia/build/nv-rm-rust/release"
# bionic：同一目标目录，选 Android RM，并显式传 NDK C linker（不是 clang++）
make -C "$WS/nvidia/waydroid-nvidia/nvidia-prolapse/media" xmlgen-android \
  RUST_PROFILE=release CARGO_TARGET_DIR="$WS/nvidia/waydroid-nvidia/build/nv-rm-rust" \
  NV_C2_RM_LIB_DIR="$WS/nvidia/waydroid-nvidia/build/nv-rm-rust/x86_64-linux-android/release" \
  RUST_LINKER="$WS/nvidia/waydroid-nvidia/build/hwcomposer-work/ndk/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android33-clang"
```

两目标均检查 ELF64、RM 动态依赖与 caps/XML 导入；Android 产物还要求 linker64，禁止 GNU libc 与开发机 RUNPATH。

nvrm 记录它链接的 Rust 库哈希，门禁拿它和 payload 里的 `libnv_bionic_native.so` 比；只换 Rust 库不重编 nvrm，
`waydroid-nvidia-setup` 会报 `nvrm (x86_64) was linked against libnv_bionic_native.so …`。

## 完整 vendor 镜像（两遍）

门禁要求镜像里的 Codec2 服务与 bundle 逐字节一致，而服务又要对着 bundle 编，所以：

```bash
.agents/skills/waydroid-a17-build/scripts/build-vendor.sh --base nvidia/build/<上一版 bundle> --out nvidia/build/<新 bundle> \
    --release v0.2.0-rc11-a17-<后缀> --note "<这一版加了什么，英文>"
```

它依次：生成 bundle（保留旧服务）→ stage → 编服务 → 带新服务再生成 bundle 并更新钉选
`nvidia/product/vendor/nvidia-prolapse/native-bundle.json` → stage → `vendorimage` → 逐字节核对。
约 5 分钟（ccache 热）。单独生成 bundle：同目录的 `make-bundle.py`。完成后在 `nvidia/product` 提交钉选。

## 同步到本仓库

- product：`rsync -a --delete --exclude=.git "$WS/nvidia/product/" nvidia-product/`
- 补丁：在源码仓库里 `git format-patch -q --start-number <N+1> -o patches/<仓库>/ <上次导出的提交>..HEAD`，
  编号接着现有文件。更新 references/patch-bases.md 里的数量。

## 不能做

- 重写 `nvidia/waydroid-nvidia` 中 `eec39aa` 及之前的提交（BUILD-RECORD 记着它，`install.sh --source` 要求后代）。
- 碰 `src/out` 以外的生成物来"修"构建；构建失败读 `/tmp/c2svc-build.log`、`/tmp/vendorimage-build.log`。
- 编完整 vendor 前不先编过一遍单模块：Soong 报错在单模块上更快暴露。
