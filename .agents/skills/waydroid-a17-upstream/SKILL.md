---
name: waydroid-a17-upstream
description: Check this project's upstreams for changes against what it pins — Shiro836/waydroid-nvidia commits since the fork point, the WayDroid-ATV system image, the patch bases of the Android source repositories, the NVIDIA driver version against the nvrm ABI table, and the LineageOS Gerrit change for the libvulkan fix — then judge which upstream fixes are worth porting. Use for "检查上游", "上游有没有更新", "upstream", "跟进上游", before a release, or when an NVIDIA driver update fails the gate.
---

# 检查上游

只读：脚本只 `git fetch` waydroid-nvidia 和查询远端，不改任何仓库。移植上游修复是另一件事，用户决定后再做。

```bash
.agents/skills/waydroid-a17-upstream/scripts/check-upstream.sh            # 先 fetch waydroid-nvidia
.agents/skills/waydroid-a17-upstream/scripts/check-upstream.sh --no-fetch
```

需要 `gh`（已登录）、`rg`、网络。工作区用 `$WAYDROID_A17_WS`，缺省取 publish 的上一级。

## 检查什么

| 段 | 对比 | 钉选来源 |
|---|---|---|
| waydroid-nvidia | `a17-local` 与 `origin/main` 的分叉点之后，上游的非文档提交 | `nvidia/waydroid-nvidia` 的 git 历史 |
| ATV system 镜像 | 最新 release 与钉选的镜像日期 | `aur/waydroid-a17-nvidia-bin/waydroid-a17-nvidia.install` |
| 补丁基线 | 各仓库上游分支头与基线提交；AOSP 的 wayland-protocols 比最新的 `android-17*` 发布 tag | `waydroid-a17-build/references/patch-bases.md` |
| NVIDIA 驱动 | 已加载版本、extra 仓库版本、NVIDIA 上游最新 tag 是否在 nvrm 版本表里；上游 waydroid-nvidia 有而我们 nvrm 没有的版本 | `nvidia/nvrm/src/compat_data.rs` |
| Gerrit 509993 | 状态和最近的消息 | `TODO.md` 第 2 项 |

## 怎么判断

- **waydroid-nvidia**：本仓库是分叉，不整版 rebase（`TODO.md`「不做」）。脚本列出的是分叉点之后上游的全部非文档提交，
  其中一部分已经移植过：`a17-local` 的移植提交用中文标题，git 认不出等价提交，要对 diff 判断。按类别取舍：
  - 值得移植：nvrm 版本表、hwcomposer 修复、setup/安装修复、对 Ada 生效的 NVK 修复。
  - NVK 改动和本仓库的双队列 NVK 在同一块代码，移植后跑 dEQP 子集和 3DMark。
  - 不移植：glibc-shim、Venus/virglrenderer、只针对 Blackwell 的 NAK 修复、上游的 README 和发版说明。
  - Codec2 的解码、能力表/XML 已换成 Rust，上游对应的 C++ 修复要在 Rust 里重写（`reports/codec2-rust.md`）。
- **ATV 出新 system 镜像**：单独评估，换镜像要重跑整套回归。
- **补丁基线**：上游有新提交时，看是否修了我们碰到的问题；变基后重新导出 `patches/` 并更新 `patch-bases.md`。
- **驱动版本不在 nvrm 版本表里**：升级这个驱动前先适配 nvrm（`tools/generate-compat.py`），再重编 vendor 和 rustnv、
  两边一起发版；之前不要升级驱动。同一大版本内通常只是在 `VERSIONS` 里加一行指向现有 profile。
- **Gerrit**：合入后，A17 的 loader 修复进入 system 镜像，`patches/external_minigbm/0009` 这个绕法可以评估去掉。

检查结论口头告诉用户；移植完成后更新 `TODO.md` 里「已移植到」的记录。
