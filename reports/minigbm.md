# minigbm：Android 17 NVIDIA 补丁移植

目标：`nvidia/work/minigbm`，ATV `lineage-24.0` 基线 `5f5797c`，本地分支 `nvidia-a17`；最终提交 `2e89bdc`。未修改正在同步的 `src/`，未推送。

## 逐补丁结果

|补丁|结果|提交与适配|
|---|---|---|
|0001 CPU usage does not force LINEAR on GPU render targets|冲突解决|`233f85d`：复用 ATV 的 `unmask64` 消耗用量标志，保留参数声明顺序、scanout/cursor、相机及 RPI4/VAAPI 对齐；CPU+渲染保留非线性布局，并接受 FRONT_RENDERING。|
|0002 pass the lock's access flags to the wrapper|冲突解决|`f2f7835`：保留 ATV 解映射无效状态返回 EINVAL 的检查，通过后调用带 READ/WRITE 标志的扩展；保留重复 lock 的标志扩宽与旧 wrapper 回退。|
|0003 FP16 and 1010102 render targets from the wrapper|冲突解决|`01f1576`：ATV 已移除静态格式组合表，改为加入 `supported_formats` 并沿用 `gbm_mesa_bo_create2` 探测；要求 wrapper 直接分配 FP16/1010102，拒绝 R8 冒充。|
|0004 P010 and a GPU-writable NV12/P010 layout for decoder output|冲突解决|`6f429c6`：P010 接入动态探测；适配新 `drv_bo_from_format(..., stride_align, ...)` 签名。NVIDIA wrapper 的布局扩展提供 256 字节 pitch、偶数高度及平面位置/容量；未导出该可选扩展的 wrapper 保留 ATV 布局，维持其他 GPU/RPI4 路径。|
|0005 import into the wrapper on the first CPU map|冲突解决|`48a7f69`：ATV 已有首次 map 导入及 4096 宽 R8 载体，复用现有函数，移除分配 usage 必须带 SW 的 map/unmap 限制；保留无 plane 参数接口，增加 map 初始化失败检查。|
|0006 YV12 for hardware decoders, carrier sized to the whole YV12 layout|丢弃（目标已覆盖）|ATV 动态探测已接受 YVU420_ANDROID+硬解标志；其载体使用 `4096 × ceil(total_size/4096)`，容纳完整 YV12，不再使用补丁所修复的半宽重塑。恢复旧静态组合表/重塑反而破坏 ATV。使用 `git am --skip`，无独立提交。|
|0007 CPU-cached memory for buffers the CPU reads often|冲突解决|`cb42bbc`：读取原始 `use_flags_copy` 判定 CPU_READ_OFTEN，防止 ATV 标志消耗使缓存请求失效；保留 test_only 不分配及 scanout 失败重试，并在重试时使用扩展入口。|

另有本地提交 `2e89bdc`（中文提交说明）：扩展查询仅用于动态 wrapper，保留 ATV 内嵌 wrapper 编译路径；无布局扩展时也使用格式字节步长，防止 P010 按半宽分配。

已导入的六个原补丁均通过 `git am -3` 导入并保留作者、原消息，消息正文追加中文适配说明；仓库身份为 `local <local@localhost>`。

## 静态自检

- `git diff --check 5f5797c..HEAD` 通过；`git status --short --branch` 仅输出 `## nvidia-a17`，工作树干净。
- 全克隆冲突标记扫描无匹配。
- 四个 wrapper ABI 头文件去除注释/空白后的声明与预编译 wrapper 源头完全一致：基础 `alloc_args/gbm_ops`、map flags、layout、alloc flags。未修改预编译库或其头文件。
- 已查明 wrapper 导出四个对应 `get_gbm_*` 符号；查明用量/映射标志、格式布局函数及签名在结果源码中存在。
- `gbm_mesa_driver/Android.bp` 已把 internals/backend 编入 `libminigbm_gralloc_gbm_mesa`，allocator/mapper@4.0 继续引用它；新增内容仅头文件，无新增 `.cpp/.c`，不需更改源文件列表。`Android.mk` 仍仅构建普通 Mesa wrapper；NVIDIA 产品需按既定产品层用预编译 wrapper 替换该模块。
- 未运行构建或项目测试；完整 Android 树尚未可用。

## 运行时待验证

1. A17 allocator/mapper@4.0 在 32/64 位进程中加载预编译 wrapper 及三个版本化扩展，分配、跨进程导入和释放正常。
2. CPU+GPU 渲染（截图、屏幕录制）保持 block-linear，READ/WRITE/重复 lock 的暂存复制方向正确；CPU-only 缓冲仍可线性映射。
3. FP16/1010102 窗口、宽色域、奇数尺寸/非整齐宽度的 pitch 与 Android plane layout 一致。
4. NV12/P010 的 256 字节 pitch、平面对齐/容量与 NVDEC、NVK、ANGLE 及宿主 Wayland 导入一致；10-bit 视频和无 Surface 的 ByteBuffer 解码正常。
5. YV12 1920×816/1080 及更宽输出容量完整、无越界；首次 CPU lock 可映射无 SW allocation usage 的解码输出。
6. CPU_READ_OFTEN 且无原始 scanout 的解码输出确实进入缓存内存，性能与同步正确；scanout 分配失败重试不改变 NVIDIA 意图。
7. 非 NVIDIA 普通 wrapper、RPI4 相机/硬解及 ATV VAAPI 路径在保留的分支上无回归；实际 A17 Soong 编译仍需完整树验证。
