# vendor image comparison

reference: `ref/vendor.img`
built: `src/out/target/product/waydroid_x86_64/vendor.img`

| class | count |
|---|---|
| identical | 729 |
| meta | 0 |
| prop | 4 |
| elf-build-id-only | 30 |
| elf-same-abi | 20 |
| elf-abi | 0 |
| content | 5 |
| only in reference | 2 |
| only in built | 0 |

## only in reference

- `/lib/hw/vulkan.nouveau.so` 
- `/lib64/hw/vulkan.nouveau.so` 

## prop

- `/build.prop` non-volatile property lines differ
- `/odm/etc/build.prop` non-volatile property lines differ
- `/odm_dlkm/etc/build.prop` non-volatile property lines differ
- `/vendor_dlkm/etc/build.prop` non-volatile property lines differ

## elf-same-abi

- `/lib/dri_gbm.so` code differs
- `/lib/egl/libEGL_mesa.so` code differs
- `/lib/egl/libGLESv1_CM_mesa.so` code differs
- `/lib/egl/libGLESv2_mesa.so` code differs
- `/lib/hw/vulkan.intel.so` code differs
- `/lib/hw/vulkan.lvp.so` code differs
- `/lib/hw/vulkan.radeon.so` code differs
- `/lib/libgallium_dri.so` code differs
- `/lib64/dri_gbm.so` code differs
- `/lib64/egl/libEGL_mesa.so` code differs
- `/lib64/egl/libGLESv1_CM_mesa.so` code differs
- `/lib64/egl/libGLESv2_mesa.so` code differs
- `/lib64/hw/vulkan.intel.so` code differs
- `/lib64/hw/vulkan.intel_hasvk.so` code differs
- `/lib64/hw/vulkan.lvp.so` code differs
- `/lib64/hw/vulkan.radeon.so` code differs
- `/lib64/hw/vulkan.virtio.so` code differs
- `/lib64/libcrypto.so` code differs
- `/lib64/libgallium_dri.so` code differs
- `/lib64/libgbm_mesa.so` code differs

## content

- `/apex/com.android.hardware.audio.apex` bytes differ
- `/apex/com.android.hardware.gatekeeper.nonsecure.apex` bytes differ
- `/apex/com.android.hardware.security.authgraph.apex` bytes differ
- `/apex/com.android.hardware.security.secretkeeper.apex` bytes differ
- `/etc/selinux/vendor_mac_permissions.xml` bytes differ
