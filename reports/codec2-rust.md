# Codec2 Rust 化

guest 里的 Codec2 服务 `android.hardware.media.c2@1.2-service-nvprolapse` 的实际工作已经全部在 Rust RM 里，
从 `a17-20261028-2` 起发布。宿主机 VA-API 驱动 rustnv 用的是同一套 RM 视频代码。

## 现在的分工

路径缩写：`M` = `nvidia-prolapse/media`，`N` = `nvidia-prolapse/driver-source/native`（都在 `nvidia/waydroid-nvidia` 的 `a17-local`）。

|部分|位置|语言|
|---|---|---|
|Codec2 组件、参数、Store、服务入口|`M/c2/NvC2Component.cpp`、`NvC2Encoder.cpp`、`service.cpp`|C++|
|编码会话薄层|`M/core/nvc2_encoder.{h,cpp}` → `nv_venc_sess_*`|C++ 壳，约 100 行|
|编码：会话、码控、五种输入转换、SSE2 分块|`N/src/video/{venc,ffi_enc}.rs`、`enc/`，头文件 `N/video/nv_venc.h`|Rust|
|解码驱动：队列、回放 CSD、多显示帧、flush/EOS、gralloc 校验|`N/src/video/{c2_dec,ffi_dec,c2_layout}.rs`，头文件 `N/video/nv_c2_dec.h`|Rust|
|能力表与 `media_codecs` XML、`nvc2-xmlgen`|`N/src/video/{caps,ffi_caps}.rs`，头文件 `N/video/nv_c2_caps.h`|Rust|

C++ 只留着 Android Codec2 接口要求的部分：组件生命周期、参数反射、C2 缓冲的读写、gralloc native handle 的外层校验。
所有 Rust 导出都有 panic 边界，ABI 在 C/Rust 两侧对 32/64 位做了布局断言。

## 和上游 Shiro836/waydroid-nvidia 的分叉

相对上游 rc11（`7670f54`），`M` 下这些文件已删除，由上表的 Rust 代码取代：

- `core/nvc2_decoder.{h,cpp}`：解码驱动。
- `core/nvc2_caps.cpp`、`tools/nvc2_xmlgen.cpp`：能力表与 XML 生成。
- `test/core_test.cpp`、`test/xml_test.cpp`、`test/nv_video_stub.{h,cpp}`：测试迁进 RM（假后端，30 项解码/布局测试）。

另外 `c2/NvC2Component.cpp`、`service.cpp` 改成调用 Rust ABI；编码器（`NvC2Encoder`、`nvc2_encoder`）是本仓库新增的，上游没有。

移植上游修复的办法：

- 上游改了 `nvc2_decoder.cpp`、`nvc2_caps.cpp` 或 xmlgen：读懂后在对应的 Rust 文件里重写，不能 cherry-pick。
- 上游改了 `c2/` 的组件代码：对照着手动合，注意我们这边调用的是 `nv_c2_dec_*`、`nv_c2_caps_*`。
- 上游改了 RM 其余部分（`N/src` 中视频 C2 以外的代码）：照常合。

## 改造时补上的处理

- 单个 VP9 输入含多张显示帧（superframe）时逐帧交付：非末帧用 `FLAG_INCOMPLETE` 克隆，末帧完成原工作。
- CSD（启动与回放的编解码专用数据）每段最多 2 MiB，超了整体拒绝并报 `C2_BAD_VALUE`。
- gralloc 句柄先在 C++ 里校验 native handle 外层（版本、fd 数、字数），再由 Rust 检查格式、几何、stride、offset、平面范围和重叠。
- MaxInputSize 用 64 位带检查的算术，溢出就拒绝并保留旧值。

## 性能

1280×720 NV12、30 fps，每轮 330 帧去掉前 30 帧，新旧实现交替各跑五轮，取中位数（ms/帧）。
计时包含提交和等待，不含文件读写和编码器开关。

|编码|码控|C 版|Rust 版|变化|
|---|---|---:|---:|---:|
|H.264|CQP|0.591|0.597|+0.98%|
|H.264|CBR|0.637|0.609|−4.38%|
|HEVC|CQP|0.455|0.443|−2.51%|
|HEVC|CBR|0.461|0.455|−1.31%|
|AV1|CQP|0.481|0.479|−0.50%|
|AV1|CBR|0.497|0.500|+0.74%|

六项里四项略快，最多快 4.4%，其余两项慢不到 1%，属于测量波动范围。
画质：五种输入格式 × 三种编码的最低 PSNR 为 39.5 dB，和 C 版相同。
解码没做计时对比，验收的是功能：四种解码各 60 帧逐帧一致，Chrome 播 VP9 60 秒 0 丢帧。

能力表和 XML 换成 Rust 后，GNU/bionic、新旧共四份 XML 输出逐字节相同，安装记录里的 `media.xml_sha256` 没变。

## 回归测试

都在 `waydroid-a17-test` skill 里：`codec-smoke.sh`（含 VP9 superframe 用例）、`surface-smoke.sh`、`web-encode-test.sh`、
`seccomp-check.sh`（冷启动和稳态两个窗口按实参对照策略）。编码计时用 `M/test/enc-benchmark.py`。
