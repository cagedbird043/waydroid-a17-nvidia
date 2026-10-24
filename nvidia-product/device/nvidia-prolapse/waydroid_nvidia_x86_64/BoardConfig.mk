# Waydroid's x86_64 board, plus the vendor sepolicy of vendor/nvidia-prolapse (file labels of our vendor modules).
include device/waydroid/waydroid/waydroid_x86_64/BoardConfig.mk

BOARD_VENDOR_SEPOLICY_DIRS += vendor/nvidia-prolapse/sepolicy/vendor
