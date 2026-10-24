# Waydroid's x86_64 product unchanged, plus vendor/nvidia-prolapse. The name keeps the _waydroid_x86_64 suffix:
# device/waydroid/waydroid/device.mk selects x86 packages (ffmpeg OMX, VNDK versions) by %_waydroid_x86_64.
$(call inherit-product, device/waydroid/waydroid/waydroid_x86_64/lineage_waydroid_x86_64.mk)
$(call inherit-product, vendor/nvidia-prolapse/prolapse.mk)

# Own device name only so that our BoardConfig.mk (vendor sepolicy) is the one the build picks; ro.product.device
# still comes from the system image's product partition (waydroid_x86_64).
PRODUCT_DEVICE := waydroid_nvidia_x86_64
PRODUCT_NAME := lineage_nvidia_waydroid_x86_64
