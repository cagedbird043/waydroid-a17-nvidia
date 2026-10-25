# Release 说明格式

中英双语，每条英文在前、中文缩进在下。以上一版为模板（`gh release view <上一个 tag> --json body -q .body`）：

```markdown
LineageOS 24.0 (Android 17) Waydroid vendor image, nvidia-prolapse mode. / LineageOS 24.0（Android 17）Waydroid vendor 镜像，nvidia-prolapse 模式。

- Pairs with the WayDroid-ATV `lineage-24.0-20261017` system image (VANILLA or GAPPS). Arch users: AUR `waydroid-a17-nvidia-bin`.
  搭配 WayDroid-ATV `lineage-24.0-20261017` 的 system 镜像（VANILLA 或 GAPPS）。Arch 用户直接装 AUR 包 `waydroid-a17-nvidia-bin`。

Changes since `<上一个 tag>` / 相比 `<上一个 tag>`：

- <用户能感知到的变化，英文>
  <中文>

Release gate PASS (22 cases + media, NVIDIA kernel module <版本>). / 发布门禁 PASS（22 个用例 + media，NVIDIA 内核模块 <版本>）。

The image is uploaded in parts / 分块上传，合并并解压：

    cat vendor.img.zst.part* > vendor.img.zst && zstd -d vendor.img.zst

Checksums: `vendor.img.zst.sha256` (parts, archive and image). `waydroid-a17-nvidia-native-x86_64.tar.zst` is the native driver bundle that matches this vendor image (native bundle `<bundle 名>`).
校验见 `vendor.img.zst.sha256`（各分块、压缩包与解压后镜像）。`waydroid-a17-nvidia-native-x86_64.tar.zst` 是与这个 vendor 镜像配套的 native 驱动包（`<bundle 名>`）。
```

变更条目写用户看得到的效果，不写内部实现；移植自上游的标出来源（如 waydroid-nvidia rc11）。
