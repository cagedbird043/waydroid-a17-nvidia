# nvidia-prolapse on Waydroid: Waydroid's lineage_waydroid_x86_64 vendor image plus the NVIDIA stack as vendor modules
# (vendor/nvidia-prolapse). Installed into the LineageOS tree by vendor-image/build-vendor.sh (stage product).
PRODUCT_MAKEFILES := \
    lineage_nvidia_waydroid_x86_64:$(LOCAL_DIR)/waydroid_nvidia_x86_64/lineage_nvidia_waydroid_x86_64.mk

COMMON_LUNCH_CHOICES := \
    lineage_nvidia_waydroid_x86_64-userdebug
