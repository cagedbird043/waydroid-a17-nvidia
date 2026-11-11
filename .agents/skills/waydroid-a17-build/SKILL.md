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

`scripts/build.sh` 默认使用 Ninja、4 个构建 job、4 CPU 时间配额及 4 CPU 亲和、32 GiB 硬内存上限，
不额外交换，nice 10、I/O idle。可用 `WAYDROID_BUILD_EXECUTOR`、`WAYDROID_BUILD_JOBS`、
`WAYDROID_BUILD_CPUS`、`WAYDROID_BUILD_CPUSET`、`WAYDROID_BUILD_MEMORY` 显式调整。
亲和由容器内 `taskset` 设置；本机 rootless cgroup 未开放 cpuset controller，不能用 `--cpuset-cpus`。
Blueprint 的 visitor 上限为 `runtime.NumCPU()*2`，单独设置 CPU 时间配额不会限制此处看到的 CPU 数量。

Go 默认 `GOMEMLIMIT=10GiB`、`GOGC=10`，由 `WAYDROID_BUILD_GOMEMLIMIT` / `WAYDROID_BUILD_GOGC` 覆盖。
`build_soong` 补丁将二者显式转发给 `env -i` 启动的 `soong_build`；Go 软目标不是 RSS 上限。
本机完整 Soong 分析仍曾触及 24 GiB 硬上限，不能把这些默认值写成已解决全树构建。
Siso 也曾仅图调度占用约 18 GiB RSS，使 20 GiB 容器中的 Java 编译被 OOM 杀死；日常桌面使用保留 Ninja 和资源限制。
OOM 后先看 cgroup 峰值与实际阶段，不循环自动加预算，不用 aapt2 等小目标通过代替 vendor 验收。

### 已冻结输入的缓存增量

只有既有 Soong/Kati 图完整成功、定义/配置被冻结时，才能直接用同版本 prebuilt Ninja 消费 combined 图。
先检查图 depfile 输入存在且未更新、used/available 环境一致、glob 结果未变，以及 Kati 图已包含当前 bundle identity；
保留原容器、绝对挂载路径和工作目录，恢复 `out/soong/ninja.environment` 的 JSON 环境。
执行参数以 `build/soong/ui/build/ninja.go` 为准，保留 keepdepfile/keeprsp、duplicate edge、
missing depfile/output 检查；先编实际 header 输出，再编 `vendorimage`，都必须在硬资源限制下完成。
本分支没有 `m --skip-soong`；`--config-only` 也不执行等价构建。
此方式是缓存增量，不是重新生成图的可复现构建；BP/MK、glob、product 参数变化后必须重新生成图，
不能改时间戳、删依赖或缩图规避。

本轮在宿主可用内存 46 GiB 时，32 GiB 硬上限、单个 Ninja job 的缓存增量已完成
`framework-minus-apex-headers` 实际输出，cgroup 峰值 `26567045120` 字节、无 OOM；
24 GiB、4 job 的同一缓存编译曾被杀。选择预算时给宿主保留余量，这不是 cold Soong 分析已通过的证据。
缓存图可用不代表全部目标产物已缓存：本轮 `vendorimage` 仍有 37,805 个动作，单 job 在一小时限时内
只完成 7,697 个正常编译动作。长编译按实际动作量设置生命周期，保持硬资源上限；不要用一小时外部限时
反复截断正常编译，也不要删掉 SwiftShader/LLVM 等真实依赖来缩图。
本轮最终缓存 `vendorimage` 在 4 job、4 CPU、32 GiB 上限内完整完成，`memory.peak=34359738368`，
`oom=0`、`oom_kill=0`；Codec2 服务及双 ABI Rust/NVRM 产物与 bundle 逐字节一致。

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

### 更新 Mesa 钉选

`mesa/build.py` 的 `PIN` 改动后，已有 `build/mesa-rm-source` 和 `build/mesa-gl-source` 不会自动切换版本。
这两个生成源码树的 git worktree 元数据使用 `/work` 绝对路径，只能在 `localhost/nvk-native-a17` 内、
将 `nvidia/waydroid-nvidia` 挂到 `/work` 后操作。先保存现有 diff，确认改动来自规范补丁栈，再获取新 tag；
用 `git cat-file -e <PIN>^{commit}` 确认对象已下载，不能用仅解析哈希的 `rev-parse --verify` 代替。
将两个生成树切到新 pin、清理生成的 overlay 后，分别运行 `build.py --prepare-only` 和
`build.py --gl --prepare-only`，确认完整补丁栈可应用。先重编 `--target host --rust-profile release`，
使 Android 构建使用同版本的 `mesa_clc` / `vtn_bindgen2`，再运行完整 `rebuild-native.sh`。
bundle 顶层 `mesa_commit` 取自两种 ABI 的实际 nvrm 构建记录，两个 pin 不一致时拒绝打包。


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
