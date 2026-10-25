---
name: waydroid-a17-release
description: Release a new version of waydroid-a17-nvidia — version the release, sync product/patches/docs, package the split vendor image and native bundle, install the local AUR package and pass the release gate, regression-test, then tag, create the GitHub release and update the AUR package waydroid-a17-nvidia-bin. Use for "发版", "打包", "release", "推 AUR", "更新 AUR", or when a release-gate failure needs fixing.
---

# 发版

只在用户明确说发版时做；推送、tag、Release、AUR 都是对外动作。脚本在 `.agents/skills/waydroid-a17-release/scripts/`（下文 `$R`）。

tag `a17-YYYYMMDD-N`（同一天第 N 版），pkgver `YYYYMMDD.N`。native bundle 名 `v0.2.0-rc11-a17-<后缀>`。

## 流程

1. **构建**：`waydroid-a17-build` skill 的 `build-vendor.sh`（native 改过先 `rebuild-native.sh`）。在
   `nvidia/product`、`nvidia/waydroid-nvidia` 提交；同步 `nvidia-product/` 和 `patches/`。
2. **文档**：README 的功能/变更、`TODO.md` 现状。
3. **提交版本号**：`$R/package.sh <tag>` 第一次会改 PKGBUILD 的 `_tag`/`pkgver` 后退出；把它和第 1、2 步的改动
   一起提交为 `发版 <tag>：<一句话>`（正文列要点）。
4. **打包**：`$R/package.sh <tag>`：压缩分块镜像、打 bundle、放进 `aur/waydroid-a17-nvidia-bin/`、`makepkg`。
   分块数必须等于 PKGBUILD `source` 里的 part 数（脚本会检查）。
5. **安装 + 门禁**：`$R/install-gate.sh <pkgver>`。要看到 `Release gate PASS: 22 cases + media` 和
   `Installed the nvidia-prolapse vendor image <bundle 名>`。
6. **回归**（`waydroid-a17-test` skill）：会话起来、GLES 是 ANGLE/NVK、`codec-smoke.sh`、`web-encode-test.sh`，
   加上这一版改动相关的场景（卡片、桌面窗口、输入法、剪贴板、文件共享、KernelSU）。
7. **推送**：`git tag <tag> && git push origin HEAD <tag>`。
8. **Release**：
   ```bash
   gh release create <tag> vendor.img.zst.part0* vendor.img.zst.sha256 waydroid-a17-nvidia-native-x86_64.tar.zst \
       --title "vendor <tag>" --notes-file <说明> --latest
   ```
   说明格式见 [references/release-notes.md](references/release-notes.md)。上传约 7 分钟。
9. **AUR**：`$R/aur-publish.sh <tag>`：删掉本地资产，按线上 URL 重算校验和、真下载重建一次、`.SRCINFO`，
   提交 `AUR：<tag> 的校验和与 .SRCINFO` 并推送本仓库和 AUR。
10. 汇报：门禁结果、回归数字、各提交号、Release 链接。

## 门禁失败

| 报错 | 原因 | 处理 |
|---|---|---|
| `nvrm (x86_64) was linked against libnv_bionic_native.so …` | 换了 Rust 库没重编 nvrm | `rebuild-native.sh`，再 `build-vendor.sh` |
| `the installed package carries release bundle …, the vendor image …` | 包更新后没跑 setup | `sudo waydroid-nvidia-setup` |
| `has no ELF64 …/linker64` | AUR prepare 的 `git apply` 在 git 仓库里静默跳过 | PKGBUILD 里保留 `GIT_CEILING_DIRECTORIES` |
| 服务不一致 / `media/xmlgen-check` 失败 | 镜像里的服务或 XML 与 bundle 不同 | 按两遍流程重编，不要手改 bundle |
| 下载上游 rc10 资产 TLS 失败 | 网络 | package.sh 会从 `$WS/nvidia/release/` 拷本地副本 |

## 规矩

- 不在 Release 前推 AUR：AUR 的 source 指向 Release 资产。
- 发版前 overlay 必须是空的（install-gate.sh 会删），否则回归测的是 overlay 而不是镜像。
- Release 资产和 makepkg 的下载、产物都在 `.gitignore` 里，不要强制加进 git。
- 本机 Waydroid 由 pacman 包 `waydroid-a17-nvidia-bin` 管理，`scripts/reinstall-vendor.sh`（走 `install.sh`）会因
  文件归 pacman 所有而拒绝；重装一律 package.sh + install-gate.sh。
