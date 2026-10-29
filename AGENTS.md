# AGENTS.md

waydroid-a17-nvidia：Waydroid Android 17 + NVIDIA 加速 + KernelSU 的发布仓库（GitHub `cagedbird043/waydroid-a17-nvidia`）。
只有作者一人开发，只在作者的机器上测试（RTX 4060 Laptop、nvidia-open 615.78.08、KDE Plasma Wayland、Arch zen 内核）。

## 仓库和工作区

本仓库是工作区 `~/Projects/waydroid-a17` 的子目录 `publish/`。源码树、构建产物、native bundle 都在工作区，
本仓库只放补丁、product 层镜像、脚本、文档、AUR 打包和 Release 资产的生成物。

| 路径 | 内容 |
|---|---|
| `README.md` | 给用户看的介绍和安装，不放开发内容 |
| `TODO.md` | 现状、计划、已知问题 |
| `patches/<仓库>/` | 各源码仓库本地分支的 `git format-patch` |
| `nvidia-product/` | 工作区 `nvidia/product` 的镜像 |
| `scripts/` | 工作区 `scripts/` 的同内容副本，从工作区运行 |
| `aur/waydroid-a17-nvidia-bin/` | AUR 包 |
| `kernelsu/`、`host/`、`container/` | KernelSU 步骤、宿主服务与 KWin 脚本、构建容器 |
| `reports/` | 移植记录、对比、跑分 |
| `docs/images/` | README 截图 |

## 做事用哪个 skill

| 任务 | skill |
|---|---|
| 编译、重编 native 栈、bundle、导出补丁 | `waydroid-a17-build` |
| 在 Waydroid 里验证、回归、截图 | `waydroid-a17-test` |
| 发版、Release、AUR | `waydroid-a17-release` |

skill 在 `.agents/skills/`，`.claude/skills` 和 `.codex/skills` 是指向它的符号链接。

## 规则

- 回复用户用简体中文。结论要实测；没验证的标 `[推测]`。
- git 由 AI 操作。提交信息用中文，身份 `cagedbird043 <cagedbird043@gmail.com>`，不加任何 AI 署名。
- 推送范围：本仓库、AUR `waydroid-a17-nvidia-bin` 和 `nvrm-vaapi-driver`、rustnv（`~/Projects/waydroid-a17/rustnv`）、
  nvrm（`~/Projects/waydroid-a17/nvidia/nvrm`）。工作区的 `src/` 各仓库、`nvidia/waydroid-nvidia`、`nvidia/product`
  只在本地提交，不推送。推送、tag、Release 只在用户要求时做。
- 不碰 NVIDIA 驱动和内核包、引导配置（包括 `lsm=`）、`@` 子卷；不重启、不注销。重启 Waydroid 会话可以。
- sudo 用临时 askpass（`/tmp/wd-askpass`，0700），用完删除。密码不进任何仓库、脚本或文档。
- 改了服务、Rust 库或 product 层就要走完整两遍构建，发版前必须过 `waydroid-nvidia-setup` 门禁。
- README 只写用户关心的东西；开发流程写进对应 skill，不在 README、TODO 里重复。
- 公开截图前检查画面内容，不放政治敏感、账号、通知等内容。
