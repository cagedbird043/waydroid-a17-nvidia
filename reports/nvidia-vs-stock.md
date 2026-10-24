# vendor image comparison

reference: `src/out/target/product/waydroid_x86_64/vendor.img`
built: `src/out/target/product/waydroid_nvidia_x86_64/vendor.img`

| class | count |
|---|---|
| identical | 747 |
| meta | 0 |
| prop | 4 |
| elf-build-id-only | 16 |
| elf-same-abi | 3 |
| elf-abi | 8 |
| content | 8 |
| only in reference | 2 |
| only in built | 33 |

## only in reference

- `/lib/libgbm_mesa.so` 
- `/lib64/libgbm_mesa.so` 

## only in built

- `/lib/egl/libEGL_angle.so` 
- `/lib/egl/libEGL_nvrm.so` 
- `/lib/egl/libGLESv1_CM_angle.so` 
- `/lib/egl/libGLESv1_CM_nvrm.so` 
- `/lib/egl/libGLESv2_angle.so` 
- `/lib/egl/libGLESv2_nvrm.so` 
- `/lib/hw/vulkan.nvidia.so` 
- `/lib/libdrm.so.2` 
- `/lib/libgallium_dri_nvrm.so` 
- `/lib/libnv_bionic_native.so` 
- `/lib/libvulkan_nouveau.so` 
- `/lib64/egl/libEGL_angle.so` 
- `/lib64/egl/libEGL_nvrm.so` 
- `/lib64/egl/libGLESv1_CM_angle.so` 
- `/lib64/egl/libGLESv1_CM_nvrm.so` 
- `/lib64/egl/libGLESv2_angle.so` 
- `/lib64/egl/libGLESv2_nvrm.so` 
- `/lib64/hw/vulkan.nvidia.so` 
- `/lib64/libdrm.so.2` 
- `/lib64/libgallium_dri_nvrm.so` 
- `/lib64/libnv_bionic_native.so` 
- `/lib64/libvulkan_nouveau.so` 
- `/odm/bin` 
- `/odm/bin/hw` 
- `/odm/bin/hw/android.hardware.media.c2@1.2-service-nvprolapse` 
- `/odm/etc/init` 
- `/odm/etc/init/android.hardware.media.c2@1.2-service-nvprolapse.rc` 
- `/odm/etc/media_codecs_c2.xml` 
- `/odm/etc/seccomp_policy` 
- `/odm/etc/seccomp_policy/android.hardware.media.c2@1.2-nvprolapse.policy` 
- `/odm/etc/vintf` 
- `/odm/etc/vintf/manifest` 
- `/odm/etc/vintf/manifest/android.hardware.media.c2@1.2-nvprolapse.xml` 

## prop

- `/build.prop` non-volatile property lines differ
- `/odm/etc/build.prop` non-volatile property lines differ
- `/odm_dlkm/etc/build.prop` non-volatile property lines differ
- `/vendor_dlkm/etc/build.prop` non-volatile property lines differ

## elf-same-abi

- `/bin/hw/android.hardware.graphics.composer@2.1-service` code differs
- `/bin/hw/android.hardware.graphics.composer@2.4-service` code differs
- `/lib64/libhwc2on1adapter.so` code differs

## elf-abi

- `/lib/hw/hwcomposer.waydroid.so` code differs
- `/lib/libgbm_mesa_wrapper.so` label u:object_r:vendor_file:s0 -> u:object_r:same_process_hal_file:s0
- `/lib/libminigbm_gralloc.so` code differs
- `/lib/libminigbm_gralloc_gbm_mesa.so` code differs
- `/lib64/hw/hwcomposer.waydroid.so` code differs
- `/lib64/libgbm_mesa_wrapper.so` label u:object_r:vendor_file:s0 -> u:object_r:same_process_hal_file:s0
- `/lib64/libminigbm_gralloc.so` code differs
- `/lib64/libminigbm_gralloc_gbm_mesa.so` code differs

## content

- `/etc/selinux/plat_pub_versioned.cil` bytes differ
- `/etc/selinux/vendor_file_contexts` bytes differ
- `/etc/selinux/vendor_keystore2_key_contexts` bytes differ
- `/etc/selinux/vendor_property_contexts` bytes differ
- `/etc/selinux/vendor_sepolicy.cil` bytes differ
- `/etc/selinux/vendor_tee_service_contexts` bytes differ
- `/etc/selinux/vndservice_contexts` bytes differ
- `/odm/etc/selinux/odm_property_contexts` bytes differ
