# Composer HAL 与 Wayland protocols 移植报告

## 交付

仅操作 `nvidia/work/` 下的独立克隆；未访问同步中的 `src/`，未推送。
两个仓库均已设置本地身份 `local <local@localhost>`，分支均为 `nvidia-a17`，工作树干净。

|仓库|基线|移植提交|
|---|---|---|
|`nvidia/work/hardware_interfaces`|WayDroid-ATV/android_hardware_interfaces，lineage-24.0，`1b0bcde9a85bd3e6c5866ae83aaab9af9b5efd29`（depth 200）|`7cb84c3d160bada81ad5d5f30fa2d690b149d79c`|
|`nvidia/work/wayland-protocols`|TUNA AOSP platform/external/wayland-protocols，android-17.0.0_r1，`2dabfe6879b25981e0340823eb1b6d037d21577f`（depth 1）|`5a5e59973b799d6e670d1e1c8d8c1c5b654003e3`|

## 逐补丁结果

### hardware/interfaces/0001：原路径干净应用，补充 A17 语义适配

以 `git am -3` 导入，保留 Shiro836 的原作者及原英文提交消息，追加中文适配说明；未丢弃任何补丁。

- A17 仍保留 `graphics/composer/2.1/utils/hwc2on1adapter/HWC2On1Adapter.cpp` 与 2.1 的 `ComposerClient.h`，原补丁无需改路径。
- primary reconnect 调用 `populateConfigs()` 时释放适配器 `mStateMutex`，以 `shared_ptr<Display>` 保持对象存活，避免和 validate/present 的锁顺序倒置。
- 重连时保留 layer/client-target handle 缓存；相同且非零的 client-target slot count 重复设置返回成功。声明、实现和 display shared_ptr 容器均已确认存在。
- **A17 必要适配：**ATV 同时打包 2.1 和 2.4 服务。2.4 的 `ComposerClient` 虽继承 2.3→2.2→2.1，但独立覆盖 `HalEventCallback::onHotplug`，仅改 2.1 不能保护该回调。经主代理确认，在同一移植提交中将相同缓存保留语义扩展到 2.4；slot-count 方法继续继承 2.1。没有改变 ATV 的服务选择或其它 2.4 回调。

### external/wayland-protocols/0001：需要，已解决基线冲突

ATV 的 `hardware_waydroid/hwcomposer/Android.bp:43-47` 静态依赖 `libwayland_extension_client_protocols`。该模块由 AOSP `external/wayland-protocols/Android.bp` 定义，scanner 输入来自其中的 freedesktop.org XML filegroup；不是 hwcomposer 仓库自带的 1.49 副本。该 filegroup 已列出所需七个 XML，无需修改构建规则。

已向 PortHwcomposer 确认其 0001/0014 的生成头依赖：协议 Android.bp 第 58、67 行分别列出 linux-dmabuf 和 xdg-decoration XML；`wayland_extension_client_protocol_headers` 使用 `wayland_scanner client-header` 及 `$(in:base)-client-protocol.h` 输出规则，`libwayland_extension_client_protocols` 通过 `export_generated_headers` 导出。因此构建规则将产出 `xdg-decoration-unstable-v1-client-protocol.h` 和含 v4 feedback 接口的 `linux-dmabuf-unstable-v1-client-protocol.h`。无需追加 hwcomposer 或协议 Android.bp 改动；此结论来自规则与 XML 的静态核对，尚未执行 scanner/构建。

Android 17 tag 的七个文件均存在，但版本/内容不足，尤其缺少 dmabuf feedback：

|XML|AOSP android-17.0.0_r1|移植后（原补丁的 1.49 内容）|
|---|---|---|
|presentation-time|presentation/feedback v1|v2|
|viewporter|v1|v1，更新规范文字|
|xdg-shell|v3|v7|
|linux-dmabuf-unstable-v1|v3，没有 feedback 接口|dmabuf/params/feedback v5，包含 hwcomposer 所需 v4 feedback|
|pointer-constraints-unstable-v1|v1|v1，更新规范文字|
|tablet-unstable-v2|接口版本 v1|接口版本 v1，更新规范文字|
|xdg-decoration-unstable-v1|v1|v2|

先执行 `git am -3`，因旧对象不在浅克隆且部分上下文不同，无法建立三方祖先；随后应用可用 hunks、手工合并剩余上下文，再 `git am --continue`。保留原作者 waydroid-nvidia project、原英文消息，并追加中文说明。

解决内容：A17 已有 dmabuf 热拔插容错、隐式修饰符说明和 presentation 枚举条目拆分，避免重复添加；合并 xdg_surface 角色检查描述，补齐 modifier v4 废弃说明、presentation `presented` 析构语义及术语更新。最终七个 XML 的 git blob SHA-1 均精确匹配原补丁目标 index（不仅接口版本相同），XML 解析全部通过。其它协议与 ATV 特性未改。

## init / VINTF 服务核对

静态源码表明 **init 会尝试启动两个 composer 服务**，不能据此宣称运行时只启动其中一个：

- `device_waydroid/device.mk:78-79` 打包 `android.hardware.graphics.composer@2.1-service` 和 `@2.4-service`。
- 两个模块的 Android.bp 都安装相应 init rc；rc 分别定义 `vendor.hwcomposer-2-1`、`vendor.hwcomposer-2-4`，均为 `class hal animation`，没有 `disabled` 或 `oneshot`；2.1 另外声明 `interface android.hardware.graphics.composer@2.1::IComposer default`。
- `device_waydroid/manifest.xml:80-85` 同时声明 `@2.1::IComposer/default` 与 `@2.4::IComposer/default`。VINTF 声明本身不负责选择启动进程。
- 两份 service.cpp 都尝试 `HwcLoader::load()`、`registerAsService()`，失败则返回 1。实际哪个进程成功注册、SurfaceFlinger 绑定哪个版本，以及是否存在重启/抢占现象，必须启动后观察；没有用推测替代实测，也没有改动现有服务策略。

## 已执行自检

- 两仓库 `git diff --check HEAD^ HEAD` 无输出；`git status --porcelain=v1` 无输出。
- 修改后的 Composer 2.1/2.4 文件与协议 XML 无冲突标记。
- 已读取相关锁、回调及继承代码；用符号检索确认 `populateConfigs()`、`getDisplayClientTargetCacheSize()`、`mDisplays` shared_ptr 容器均存在。
- 七个 XML 均通过解析，并精确匹配原补丁目标 blob。
- 未运行构建、项目测试或设备运行测试（源码树尚未就绪）。

## 运行时待验证

1. 用 `getprop init.svc.vendor.hwcomposer-2-1`、`getprop init.svc.vendor.hwcomposer-2-4`、进程列表、`lshal` 和启动日志确认实际服务注册与 SurfaceFlinger 绑定，检查是否反复重启或替换注册。
2. NVIDIA/KWin 下播放或渲染时连续 resize、最大化/还原；确认主显示重连更新尺寸，没有死锁、BAD_LAYER、释放后使用或 SurfaceFlinger/HAL 崩溃。
3. 确认新 display 的 client-target slot count 可重复设置；旧 layer 缓存随 destroyLayer 释放，client-target handles 随 slot 更新释放，长时间 resize 不累积资源。
4. 验证 dmabuf v4 feedback 的设备及格式/修饰符解析，同 GPU 直接呈现与跨 GPU PRIME-copy 均正确；新 XML 可与宿主较低版本协商。
5. 验证 presentation timing、viewporter 裁剪、xdg-shell resize/装饰、pointer constraints 和 tablet 输入；保留 ATV task streams、multi-window 与 touchpad 的行为。
