# Android 17 HWUI：NVK 双 graphics queue

## 结果

- 双 ABI 原生 NVK 与 vendor 镜像已构建成功；本任务没有停止、启动或修改运行中的 Waydroid。
- 真实 Android 17 bionic x86_64 / i686 的独立 public Vulkan probe 均报告 `graphics_family=0 queueCount=2`，并通过两线程并发提交、GPU fill 与 CPU readback。
- 最终组合为**本地新 NVK + rc10 原 Rust RM backend/HAL/libdrm/nvrm/Codec2**，probe 测的就是该组合。
- vendor.img 内 19 个 bundle prebuilt 均与新 bundle 逐字节一致；镜像 build_record 属性等于新 BUILD-RECORD.json SHA256。

| 项目 | 路径 / 身份 |
|---|---|
| 源码提交（`a17-local`，未推送） | `eec39aa`：为 Android 17 HWUI 暴露两条独立 NVK graphics 队列 |
| product 提交 | `c5aaf35`：固定 Android 17 HWUI 双队列 NVK 原生包身份 |
| 新完整 native bundle | `nvidia/build/native-multiqueue/`（含 payload、原 gates、新 BUILD-RECORD、SHA256SUMS.native） |
| 新 bundle release | `v0.2.0-rc10-a17-multiqueue` |
| BUILD-RECORD SHA256 | `684a32a51133fe326904a67bc2a905e95cce52c0da5949dbd5bbeff0992c3565` |
| vendor 镜像 | `src/out/target/product/waydroid_nvidia_x86_64/vendor.img` |
| vendor 镜像大小 / SHA256 | 898494464 bytes / `65f00c4df7d2d454ebc183b22c646ddadb27768885646e55e88b8f80ea1e44d4` |
| 原生修改版构建日志 | `logs/nvk-multiqueue-native-build.log` |
| vendor 构建日志 | `logs/nvk-multiqueue-vendorimage.log`（`build completed successfully (01:36)`） |
| 镜像只读核对记录 | `nvidia/waydroid-nvidia/build/nvk-multiqueue-probe/image-check/result.json` |

## 为什么必须是真正独立的队列

A17 `frameworks/base/libs/hwui/renderthread/VulkanManager.cpp:232-244` 在首个 graphics family 要求两条队列，`:441-442` 取得 queue 0 和 queue 1；`:543-544` 将 RenderThread context 绑定 queue 0，upload context 绑定 queue 1。

第二条不是备用句柄：`HardwareBitmapUploader.cpp:108-117` 创建 **GrallocUploadThread**；`:239-261` 在该线程创建 `kUploadThread` Ganesh context，向 AHardwareBuffer 上传位图并执行 `submit(GrSyncCpu::kYes)`。其 `mVkLock` 不会串行化 RenderThread 的提交，两个线程可并发进入驱动。

已阅读 native README、Mesa README、RM-ADAPTER、SYNCHRONIZATION、ASYNC-SUBMISSION、nvkmd_rm.c、rm-integration.patch，以及 pin Mesa 的 queue-family / queue 创建代码。Mesa pin 是 `ddaf85e353442d9d7f192fdcf1823e652e3f2ee3`（26.2.5）。

### 现有实现已具备每 VkQueue 的独立 submission context

1. Mesa `nvk_device.c:370-374` 对每个 queue index 调用 `nvk_queue_create`。
2. Mesa `nvk_queue.c:409-447` 每次分配新 queue、`exec_ctx`、draw constant buffer、push stream 和初始化 graphics/compute state。
3. `nvkmd_rm.c:1238-1263` 每次分配新 C context，并调用 `nv_rm_context_create`；pending pushes、waits、last token 均为 context 私有。
4. Rust `src/mesa.rs:1357-1385` 每次创建新 `Queue`，追加到动态 `Vec<Option<Queue>>`，未设单 graphics queue 上限。
5. `src/gpu.rs:1350-1544` 每次创建独立 notifier、GPFIFO、tail、TSG（0xa06c）、context-share（0x9067）、channel、USERD、completion surface 和 retirement slot。每个 TSG 的 `subcontext=0` 是本 TSG 内索引，不是整设备共用一条 graphics channel。
6. `Bridge.inner` mutex 保护共享 Rc graph、分配器、sync payload 和 scratch；提交在锁内操作指定 context 的 ring，ring pressure 的 CPU wait 位于 C adapter 重试循环，不持该 mutex。同步、回收按 context id/token 跟踪。

因此最小修改只是 `native/mesa/nvk-rm-graphics-multiqueue.patch` 将 graphics family `queue_count` 改成 2。`build.py` 将 patch 接入 NVK patch stack，`native_rust_profile.py` 将其加入源码 hash 快照；README 说明所有权和 probe。无需重写 Rust backend、把两个 VkQueue 映射到同一 ring，或增加 worker。

## 构建环境与原版 faithful rebuild

使用官方 `packaging/native/Containerfile`，在 rootless Podman 内复现；没有向宿主安装 toolchain 或修改驱动。基础镜像 digest `fe6972d4dc1f660c0c10f4c41b2de8986bab89e7e2955378f8beadb8ebcd7433`，Arch archive snapshot `2026/10/15`。本地最终构建镜像 `localhost/nvk-native-a17`，ID `ce24d8fb2965454c17907d0097c32fa59fe7ac76dbd4966ff16103e5d045e072`。

工具版本：Rust 1.95.0（59807616e）、Cargo 1.95.0、Android x86_64/i686 targets、Meson 1.12.1、Ninja 1.13.2、host GCC 16.2.1、LLVM/Clang 23.1.1、NDK r29 `29.0.14206865` API33（NDK Clang 21）、bindgen 0.72.1、cbindgen 0.29.2、libdrm 2.4.134、Android 静态 libelf 0.8.13，以及 `host-build-deps.json` checksum-pinned libclc/SPIR-V translator。完整容器 package 版本写入新 record 的 `nvk_build_environment`。

网络：Arch 默认网络曾超时，host network 成功；Rust 官方站 TLS EOF，使用 rsproxy 获取同一 Rust version pin。保留已完成系统依赖层，再安装 Rust 并保存容器镜像。`hwcomposer/provision.sh ndk clones imagelibs` 提供 pinned AOSP headers 与 Android13 link-time libs；双 ABI libdrm 使用仓库原 Makefile 构建。probe 运行时则从当前 ATV **Android17** `ref/system.img` 只读抽取真实 bionic closure。宿主已有 `dump.erofs`，不需增加软件包。

先在**未接入双队列 patch** 的源码上成功构建 host、Android x86_64、Android i686。rc10 BUILD-RECORD 所列全部 native source hashes 与构建前源码一致。baseline 保留在 `nvidia/waydroid-nvidia/build/nvk-baseline/{host,android,android32}/`；完整比较在 `comparison.json`、`sections.json`。

| ABI / 文件 | 本地 baseline SHA256 | rc10 SHA256 |
|---|---|---|
| x86_64 NVK | `e15bc94d85325849ec20d62781442e1e3e5452f8418552244fad024c12540c28` | `560d18fb2c6207fcb2b022663788bea46e5eaab06f05ff9083f9acb00b9ad2cb` |
| i686 NVK | `ba0e19d3061e93cca4f476bd0e05b9c755f9f6da764dcb11d2341ce69985c89f` | `c31ea568ace09ade5c87bf018ffaaaf18655690853372eba7e455ad1ed5bc09a` |
| x86_64 Rust RM | `8ec8824b776eed4fec5fdfa845629cdf6101af1eb81fcaf6b5f64f0cbfaff4b4` | `3ef545204f8f4ea9f9df9ae258ddf233600cdb2fab307d348b05e1a3d793eea3` |
| i686 Rust RM | `f33bcf628ba828be90d92fd70a31cb6cd0a668b0a65e44308717ed45c5ed6ca3` | `3ddde70d7f4c7abeab0f74474329377453c1883415d3a29792c3edf9af72cd60` |

不是整个 ELF 逐字节相同：本地 prefix `/work` 与作者 `/home/forsen/native-ci/waydroid-nvidia` 不同。pyelftools 比较所有 SHF_ALLOC、非 NOBITS section：**两个 Rust RM 文件全部运行时 section 相同**；两个 NVK 的 `.text`、`.rodata` 等代码/常量 section 相同，差异限于动态字符串、链接地址/重定位、data 指针表及 build-id。`readelf -d` 确认 rc10 自身有作者绝对路径 RUNPATH，本地同配方为 `/work` 路径，影响字符串表长度和链接布局。[INFERENCE] NVK 布局差异由此解释，未声称已语义归一化证明全部重定位。

## 修改版产物与 probe

| ABI | 最终 `libvulkan_nouveau.so` SHA256 |
|---|---|
| x86_64 | `fbc2cd2d3ea44f5b29bbcb36113ca3fd6ac3f8ddf0eb952e1c10f3752f3f4bb3` |
| i686 | `54cd8dccafcfbf5e85f814945542fa8002259b773341560880bb1d8ad2f01b0f` |

原构建产物在 `nvidia/waydroid-nvidia/build/nvk-{android,android32}/src/nouveau/vulkan/libvulkan_nouveau.so`，实际部署副本在新 bundle 的 `payload/vendor_extra/{lib64,lib}/`。HAL `hw/vulkan.nvidia.so` 是原 rc10 wrapper，其 queue-family 查询转发给 NVK；不需要修改/重建 wrapper。

最终 bundle 只替换这两个 NVK，保留原 Rust backend bytes。`nv_rm.h` 未改，Rust runtime sections 的 baseline 比较一致；保留原 bytes 使 nvrm 的原构建关联和 `nvrm_rust_sha256` 继续真实。新 record 清楚区分 `base_release`、保留 backend 的 `rust_builds`、本地 NVK 的 `nvk_builds` 及其构建时 backend metadata、最终实际 backend hash；没有冒充整栈全部本地重编。

新 probe `tools/native-vulkan-multiqueue.c` 用 NDK r29/API33 编译，选择 NVIDIA/Mesa NVK，打印首 graphics family，创建同 family 两条不同 VkQueue。每线程持有自己的 command pool/buffer/fence；每轮 pthread barrier 同时释放两个提交者，完成后逐 word 验证 GPU fill。每 ABI 512 submissions、524288 个 word。

真实输出（两个 ABI 相同）：

```text
device=NVIDIA GeForce RTX 4060 Laptop GPU (NVK NV197) driver=NVK Mesa 26.2.5 (git-ddaf85e353)
graphics_family=0 queueCount=2
PASS: two concurrent graphics queues, 512 submissions, 524288 words checked
```

证据目录 `nvidia/waydroid-nvidia/build/nvk-multiqueue-probe/`：

- `logs/android-multiqueue.log`、`logs/android32-multiqueue.log`；exit 均为 0。
- `results.json`、`runtime-origin.json`；32-bit 使用 release gate 的 user/PID namespace runner，避免 bionic 对 host 高 PID 的限制。
- `runtime/{lib64,lib}` 为 A17 system 的只读提取副本；没有写入 guest。

原生修改版双 ABI 构建使用 `build.py --target android/--target android32 --rust-profile release -j 12`，离线完成。32-bit 保留上游已有 64-bit atomics 对齐 warning，没有将其屏蔽；本次 probe 通过不代表解决所有上游警告或 Vulkan conformance。

## Product、vendor 与 host gate

product `vendor/nvidia-prolapse/native-bundle.json` 固定项目根目录相对 bundle path 和 record hash。`scripts/stage-product.sh` 读取它，先核对 record hash 和 payload hashes，再复制 payload 到 `src/vendor/nvidia-prolapse/prebuilts/native/payload`，生成 `identity.mk`。`scripts/reinstall-vendor.sh` 的 OTA 包装也读取同一 pin，避免错误使用 rc10 record。这两个项目根 scripts 不属于 product git；product commit 跟踪 pin 本身。

已运行：

```sh
scripts/stage-product.sh
scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug vendorimage
```

`vendor_image.check_prebuilts` 只读提取并核对镜像中的 19 个 prebuilt：全部与新 bundle 一致。读取 vendor build.prop 确认：

```text
ro.vendor.nvidia_prolapse.version=v0.2.0-rc10-a17-multiqueue
ro.vendor.nvidia_prolapse.build_record=684a32a51133fe326904a67bc2a905e95cce52c0da5949dbd5bbeff0992c3565
```

`release_gate.verify_bundle` 通过，新 record 精确覆盖 68 个 payload/gate 文件。安装 gate 还需要在目标 GPU/内核 tuple 上执行完整 Vulkan/GL/Codec2 cases；本任务只执行双队列专项 probe 和只读 image/bundle 核对，没有执行安装 gate。

### 主代理的准确 host 安装步骤（本任务未执行）

1. 若需要重新安装 host 工具，先执行 host installer。其 wrapper 当前固定 rc10 release，会写入原 native bundle；因此须在下列新 bundle cutover **之前**完成。
2. 由主代理完成 Waydroid 的安全停止，确认 setup 要求的 stopped 状态。
3. 从项目根目录同步**完整新 bundle**到 host 的固定目录：

   ```sh
   sudo rsync -rlp --checksum --delete \
     nvidia/build/native-multiqueue/ \
     /usr/lib/waydroid-nvidia/native/release/
   sha256sum /usr/lib/waydroid-nvidia/native/release/BUILD-RECORD.json
   # 应为 684a32a51133fe326904a67bc2a905e95cce52c0da5949dbd5bbeff0992c3565
   ```

4. 使用已修改、读取 product pin 的项目脚本打包并安装匹配 vendor：

   ```sh
   scripts/reinstall-vendor.sh
   ```

   它调用 `packaging/vendor-ota.py` 生成 `out-ota/`，将 OTA zip/channel 安装到 `/usr/lib/waydroid-nvidia/vendor/`，然后运行 `sudo env LC_ALL=C waydroid-nvidia-setup`。setup 校验新 bundle、zip/channel、image prebuilts 和 build_record，在 GPU/已加载内核上运行完整 release gate，成功后更新安装记录及 codec XML。
5. 由主代理启动并设置/验证 `debug.hwui.renderer=skiavk`，检查 HWUI/RenderThread/GrallocUploadThread 日志、画面与 NVIDIA Xid。专项 probe 不替代这一步。

Gate 依据：`release_gate.py:73-92` 校验 bundle 文件集合和 hashes；`vendor_image.py:151-162,240-259` 校验 image bytes、record digest 与 GPU gate。`/usr/lib/waydroid/tools/helpers/nvidia_native.py:1620-1677` 在启动时核对 image identity、安装记录、已安装 package record、image hash、kernel version 和 codec XML。不能仅覆盖 vendor.img 或手改 build.prop 绕过 gate；须使 host bundle、镜像和 setup 安装记录同时一致。

## 开放风险与边界

- Android 的真实 `skiavk` 启动、hardware bitmap upload 和可见画面由主代理安装后验证；本任务没有声称已完成 Android UI 验收。
- 独立 TSG/channel 不等于独立物理 graphics engine；GPU 可以时间片调度，Vulkan 不保证物理同时执行。
- 现有 foreign sync-file、device-loss、回收和 GPU semaphore 约束保持不变，见 `SYNCHRONIZATION.md`。
- 延续原配方的开发 RUNPATH（新产物为 `/work/...`）；Android 实际库查找依赖 vendor namespace/SONAME，probe 明确使用 bundle LD_LIBRARY_PATH。没有在本任务加入额外 RUNPATH 清理或改写无关运行时逻辑。
- 未更换 host NVIDIA 驱动、内核包、引导配置；没有重启或操作 Waydroid 生命周期。
