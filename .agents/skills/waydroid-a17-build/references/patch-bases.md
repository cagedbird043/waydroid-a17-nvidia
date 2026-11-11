# 补丁基线

`patches/<目录>/` 是各仓库本地分支在下列基线之上的提交（`git format-patch`），按编号顺序 `git am`。

| 目录 | 树内路径 | 上游 | 分支 | 基线 | 补丁数 |
|---|---|---|---|---|---|
| `hardware_waydroid` | `hardware/waydroid` | https://github.com/WayDroid-ATV/android_hardware_waydroid | lineage-23.0（ATV manifest） | `3af187c1de51` | 34 |
| `external_minigbm` | `external/minigbm` | https://github.com/WayDroid-ATV/android_external_minigbm | lineage-24.0 | `5f5797cacd14` | 9 |
| `hardware_interfaces` | `hardware/interfaces` | https://github.com/WayDroid-ATV/android_hardware_interfaces | lineage-24.0 | `1b0bcde9a85b` | 1 |
| `external_wayland-protocols` | `external/wayland-protocols` | https://android.googlesource.com/platform/external/wayland-protocols | AOSP | `2dabfe6879b2` | 3 |
| `device_waydroid_waydroid` | `device/waydroid/waydroid` | https://github.com/WayDroid-ATV/android_device_waydroid_waydroid | lineage-24.0 | `ce2f57ee2768` | 4 |
| `vendor_waydroid_init` | `vendor/waydroid/init` | https://github.com/WayDroid-ATV/android_vendor_waydroid_init | main | `e97b43d97f70` | 2 |
| `waydroid-nvidia` | `../nvidia/waydroid-nvidia` | https://github.com/Shiro836/waydroid-nvidia | public-test | `29ffa3a237b0` | 73 |
| `build_soong` | `build/soong` | https://github.com/LineageOS/android_build_soong | lineage-24.0 | `d40efa6ca919` | 1 |

`waydroid-nvidia` 的补丁 AUR 包在 prepare() 里用 `git apply` 打（补丁含二进制测试码流），并要求
`GIT_CEILING_DIRECTORIES`，否则在 git 仓库里运行 makepkg 时会静默跳过所有路径。

从零搭建：`podman build --build-arg ROOT="$WS" -t localhost/waydroid-a17-build container`（构建容器按原路径挂载工作区，
Mesa 交叉编译用树里的 lld）→ `scripts/sync.sh` → `apply-waydroid-patches` → 各仓库 `git am` → `scripts/stage-product.sh`
→ `scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug vendorimage`。源码约 100 GB。

## 保存的 system 安全源码

以下系列保留已移植的源码，尚未构建、签名和部署为 system 镜像，不代表完整的 2026 年 11 月 ASB，也不提高 SPL。
当前运行的 system 仍为 ATV 镜像，SPL 为 `2026-10-01`。本地默认 AOSP 测试平台证书与 ATV 平台证书不同；
部署 system 必须先解决正式签名与现有数据的兼容，不能绕过签名校验或清数据升级。

| 目录 | 树内路径 | 基线 | 补丁数 |
|---|---|---|---|
| `.repo_manifests` | `.repo/manifests` | `b51a0c449a32` | 4 |
| `frameworks_av` | `frameworks/av` | `f18c3ac08a56` | 5 |
| `frameworks_base` | `frameworks/base` | `6e3f1fcdf5d2` | 45 |
| `frameworks_native` | `frameworks/native` | `95cdabea07cb` | 4 |
| `packages_apps_Settings` | `packages/apps/Settings` | `51beb5b15d0c` | 2 |
| `external_aac` | `external/aac` | `41f344ffc0ba` | 1 |
| `external_hplip` | `external/hplip` | `d37ce064e1e2` | 1 |
| `external_tremolo` | `external/tremolo` | `100623061b6d` | 1 |
| `external_libopenapv` | `external/libopenapv` | `1f7d75914d98` | 1 |
| `packages_apps_ManagedProvisioning` | `packages/apps/ManagedProvisioning` | `dcb981579cbb` | 1 |
| `packages_modules_IntentResolver` | `packages/modules/IntentResolver` | `514e2233f8c1` | 1 |
| `packages_modules_NeuralNetworks` | `packages/modules/NeuralNetworks` | `a44a9032ab9a` | 1 |
| `packages_modules_Profiling` | `packages/modules/Profiling` | `8b3abe8eebc0` | 1 |
| `packages_services_Iwlan` | `packages/services/Iwlan` | `ddf0eb7f277e` | 1 |
| `system_gsid` | `system/gsid` | `35a92d40f529` | 1 |
| `trusty_user_base` | `trusty/user/base` | `165d46c463bd` | 1 |

`.repo_manifests` 包含清华镜像配置和三个 Lineage 安全 fork 声明。先在对应基线应用补丁，再同步各组件、应用各系列；
实际完整基线与补丁后本地 HEAD 保存在 `container/system-security-revisions.json`，用于核对源码，不作为远端可获取的 revision。
