# 补丁基线

`patches/<目录>/` 是各仓库本地分支在下列基线之上的提交（`git format-patch`），按编号顺序 `git am`。

| 目录 | 树内路径 | 上游 | 分支 | 基线 | 补丁数 |
|---|---|---|---|---|---|
| `hardware_waydroid` | `hardware/waydroid` | https://github.com/WayDroid-ATV/android_hardware_waydroid | lineage-23.0（ATV manifest） | `3af187c1de51` | 32 |
| `external_minigbm` | `external/minigbm` | https://github.com/WayDroid-ATV/android_external_minigbm | lineage-24.0 | `5f5797cacd14` | 9 |
| `hardware_interfaces` | `hardware/interfaces` | https://github.com/WayDroid-ATV/android_hardware_interfaces | lineage-24.0 | `1b0bcde9a85b` | 1 |
| `external_wayland-protocols` | `external/wayland-protocols` | https://android.googlesource.com/platform/external/wayland-protocols | AOSP | `2dabfe6879b2` | 3 |
| `device_waydroid_waydroid` | `device/waydroid/waydroid` | https://github.com/WayDroid-ATV/android_device_waydroid_waydroid | lineage-24.0 | `ce2f57ee2768` | 4 |
| `vendor_waydroid_init` | `vendor/waydroid/init` | https://github.com/WayDroid-ATV/android_vendor_waydroid_init | lineage-24.0 | `e97b43d97f70` | 2 |
| `waydroid-nvidia` | `../nvidia/waydroid-nvidia` | https://github.com/Shiro836/waydroid-nvidia | public-test | `29ffa3a237b0` | 43 |

`waydroid-nvidia` 的补丁 AUR 包在 prepare() 里用 `git apply` 打（补丁含二进制测试码流），并要求
`GIT_CEILING_DIRECTORIES`，否则在 git 仓库里运行 makepkg 时会静默跳过所有路径。

从零搭建：`podman build --build-arg ROOT="$WS" -t localhost/waydroid-a17-build container`（构建容器按原路径挂载工作区，
Mesa 交叉编译用树里的 lld）→ `scripts/sync.sh` → `apply-waydroid-patches` → 各仓库 `git am` → `scripts/stage-product.sh`
→ `scripts/build.sh lineage_nvidia_waydroid_x86_64-cp2a-userdebug vendorimage`。源码约 100 GB。
