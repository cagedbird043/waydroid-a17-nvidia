# hwcomposer NVIDIA 补丁移植报告

## 结果

- 仓库：`nvidia/work/hardware_waydroid`，ATV `lineage-23.0` 基线 `3af187c`，本地分支 `nvidia-a17`。
- 最终提交：`a309b1c`。18 个补丁中，17 个按顺序独立导入；0009 已由 ATV 等效实现而跳过。另有 1 个中文提交完成连接/释放生命周期适配。
- 导入提交保留原作者和原始消息；有适配的提交追加中文说明。没有推送，也没有操作同步中的 `src/`。
- 0014–0016、0018 的补丁所列旧 blob 无法由 `git am -3` 重建祖先；保持该 am 会话，按可应用块及原补丁内容完成适配，再执行 `git am --continue`。

## 逐补丁结果

| 补丁 | 结果 / 提交 | 处理 |
|---|---|---|
| 0001 baseline | 已解决，`a410dba` | 导入 NVIDIA 格式/修饰符准入、不透明 RGB 导入、服务器端装饰、客户端目标绘制修正和剪贴板修正；协议对象与输入序列号迁至 `wl_conn`。保留 ATV task streams、任务关闭/快照、几何所有权和按连接停线程后回收；使用 ATV 单配置 resize 路径，不引入 A13 的固定物理分辨率模式阶梯。 |
| 0002 formats mutex | 已解决，`16aaf5f` | 每个 `wl_conn` 独立持有格式、修饰符和互斥锁；广告回调与导入准入读写同一连接的数据。 |
| 0003 NVIDIA EGL LINEAR | 已解决，`2eb7616` | 按连接记录存在 NVIDIA modifier 的格式，只对这些格式拒绝 LINEAR。 |
| 0004 wl_buffer cache | 已解决，`8b80a68` | 保留 ATV `shared_ptr` 和已附着缓冲保活；ctl 缓存按 8 帧未使用策略清理，增加 dma-buf inode 身份，不在几何变化/热插拔时整体清空。 |
| 0005 no abort | 已解决，`29cd2e6` | 帧错误返回失败；缺少 shell 协议的检测移至 `wl_conn_open`。保留 ATV 的断线重连。 |
| 0006 named disconnect | 已解决，`ab097f7` | 导入协议对象/错误码日志和 `waydroid.hwc.wayland_lost`。保留 ATV ctl 重连与独立 task 连接回收，不以进程退出 75 终止其他任务。 |
| 0007 SIGPIPE | 已解决，`a043b2f` | 忽略 SIGPIPE，同时保留 ATV 启动时清理陈旧窗口属性。 |
| 0008 cursor importability | 已解决，`e35458e` | ctl 连接上的游标准入检查及 wl_shm 回退；保留 ATV 已有 acquire-fence 处理。 |
| 0009 HIDL threadpool | 已丢弃：等效补丁 | ATV `bb49e33` 已不再缩小 composer 服务配置的线程池；保留它的实现，避免重新配置已启动的线程池。 |
| 0010 SHM fallback | 已解决，`87cacbd` | 无法直接导入的层使用当前 ctl 的 wl_shm，继续采用 ATV 的共享所有权。 |
| 0011 acquire timeout | 已解决，`2623322` | 保留 `shared_ptr` 参数；1 秒 fence 等待失败后仍完成呈现几何/反馈。0014 中将等待放在 GPU 复制和 attach 之前。 |
| 0012 monotonic timestamps | 已解决，`5522f39` | presentation clock 按连接保存；ctl 反馈仅在 CLOCK_MONOTONIC 时进入 vsync。保留 ATV 的 task-streams 模式唤醒逻辑。 |
| 0013 viewport clamp | 干净应用，`ecd4984` | 裁剪矩形限制在经过旋转变换的缓冲范围内。 |
| 0014 cross-GPU PRIME | 已解决，`f079758` | dmabuf v4 feedback、present_path、复制池迁至 `wl_conn`；FBT 保留共享缓存和 fence 时序；连接重建/销毁时释放复制源、复制池和 feedback。同时完成下述 task-stream 新增适配。 |
| 0015 YUV / planes | 已解决，`cc680d2` | 保持 wl_conn API，传递所有平面；YUV 交给 SurfaceFlinger，SHM 不支持的格式明确失败；cros 平面数组构造前检查 DRV_MAX_PLANES 范围。 |
| 0016 hotplug outside present | 已解决，`a3a579c` | 移除 `hwc_set` 的主显示 hotplug 与 needHotplug；保留 ATV 输入管道更新及帧请求，并加 poison 防止 present/Wayland 文件直接发送 hotplug。 |
| 0017 Soong prime-copy | 干净应用，`741cd44` | Android.bp 编入 prime-copy.cpp，增加 Vulkan headers，保留缺失字段初始化警告设置。 |
| 0018 safe resize | 已解决，`50f55a6` | 复用 ATV 窗口几何所有权与 250ms settle；将 resize worker 移到独立 display-resize.cpp。仅 `ro.vendor.composer.safe_primary_reconnect=true` 时从该线程发送主显示重连，不持有模块锁调用 HAL。保留单一 config，物理尺寸由 modes_mutex 保护；不引入第二套模式阶梯/线程。Android.bp 同时编入新文件。 |

## 新增适配：ATV task streams

ATV 的 `post_task_buffer` 原来固定使用 android_wlegl。NVIDIA/KWin 的 dmabuf 图形路径不能仅依赖这个协议，因此：

- 当前连接支持 android_wlegl 时保留 ATV 原路径。
- 否则使用当前任务的 `wl_conn` 导入 dmabuf：同 GPU 直接导入，跨 GPU 使用 PRIME 系统内存 LINEAR 复制。
- 保留 slot 的 inode/元数据重分配判断、fence 等待、初次 configure 前暂存、去激活时保留最新帧及原有 slot 释放策略。
- dmabuf 的 `wl_buffer.release` 使用生命周期稳定的连接作 userdata，再按连接及 wl_buffer 查找 slot；避免回调引用已经被替换的 buffer。
- 复制池随各连接回收；主连接重连不丢弃其他任务连接。
- 上述释放回调稳定性、重连格式集合加锁及编译清理在中文提交 `a309b1c` 中完成。

## 自检证据

- `git diff --check 3af187c`：通过，无输出。
- `git status --short --branch`：仅 `## nvidia-a17`，工作树干净。
- hwcomposer 源码冲突标记搜索：无匹配；`.rej` / `.orig` 搜索：无文件。
- 已阅读相关代码，并搜索新增 PRIME、resize、task-stream release、displayable_buffer、set_crop 的声明/定义/调用；Android.bp 同时列出 prime-copy.cpp、display-resize.cpp。
- 协议依赖：PortComposerHal 已确认配套 wayland-protocols 分支更新含 xdg-decoration 和 dmabuf feedback 接口，既有 `libwayland_extension_client_protocols` 导出生成头；本 slice 不新增生成规则。
- 未构建、未运行项目测试、未启动 Waydroid。静态自检不等同于 Android 17 编译或运行验证。

## 需要运行时验证

1. **同 GPU 直通**：NVIDIA/KWin 下 full UI、单窗口、传统多窗口及 task streams 均有图像；确认 ANGLE/NVK、block-linear modifier、`waydroid.hwc.present_path=direct`；游标/透明度/装饰/剪贴板正常。
2. **新增 task-stream 路径**：分别使用 task streams 和传统多窗口反复开启/关闭/切换至少两个应用；验证每连接窗口、focus、去激活快照及恢复、初次 configure、slot 释放，无持续 EBUSY、黑卡或 fd 增长。
3. **跨 GPU**：在 iGPU compositor 下验证 FBT 与 task-stream 的 PRIME 路径，检查 `cross-gpu-copy`、系统内存 LINEAR pitch、缓冲池 release、持续动画与快速窗口切换/resize；包括暂存帧被后续帧替换的情况。确认失败复制不会附着原 NVIDIA 显存缓冲。
4. **连接故障隔离**：重启/断开 compositor 或关闭单个 task 的主机连接，检查命名错误属性；ctl 能重连，独立任务连接能单独回收/重开，其他任务不被杀死，无旧 wl_buffer/复制池代理被复用。
5. **安全 resize**：使用配套修正后的 composer HAL，并分别测试 safe_primary_reconnect 属性开启/关闭。开启时拖动、最大化、分数缩放和固定尺寸下 Android 尺寸只在 settle 后变化，不从 present 内嵌套回调、不死锁/崩溃；关闭时无主显示重连。特别检查 ATV 几何所有权下单窗口/多任务不互相改尺寸，拖动期间 viewport 呈现与触摸坐标一致。
6. **视频与格式**：Chrome/ExoPlayer 等 YUV 子层由 SurfaceFlinger 合成，色域/范围正确，无 Wayland invalid_wl_buffer；确认多平面参数完整、SHM 不支持格式只失败而不杀连接。
7. **缓存与同步**：连续几何变化、重分配同大小缓冲、关闭应用后缓存老化正常；1 秒 acquire 超时、游标 acquire fence、CLOCK_MONOTONIC 及非单调 presentation clock 均不造成冻结/持续 fd 泄漏。
