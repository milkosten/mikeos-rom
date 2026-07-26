# =============================================================================
# MikeOS daemon-as-system — install rules (Milestone 3.2 / Part A).
#
# Kept in a SEPARATE mk (inherited from config/common.mk) so this whole layer is
# easy to review and toggle: comment out the one inherit line in common.mk to
# drop daemon-as-system entirely.
#
# This wires three things into the ROM:
#   1. the init service .rc               -> /vendor/etc/init/mikedaemon.rc
#   2. the hardened launcher (executable) -> /system/bin/mikeos-daemon
#   3. the mikedaemon sepolicy dir        -> BOARD_VENDOR_SEPOLICY_DIRS
#
# ---------------------------------------------------------------------------
# KNOWN-UNVERIFIED (resolve on the NEXT build — see README.md):
#   * TARGET_COPY_OUT_VENDOR vs _SYSTEM partitions. The .rc goes to the VENDOR
#     partition's etc/init (init auto-imports /vendor/etc/init/*.rc). The
#     launcher goes to the SYSTEM partition's bin. If this device is
#     system-only (no separate vendor partition) these may resolve to the same
#     image, which is fine. Confirm both land + are auto-imported on first boot.
#   * BOARD_VENDOR_SEPOLICY_DIRS is a BoardConfig-time var. Setting it from a
#     product .mk works in current AOSP/LineageOS, but if the sepolicy dir is
#     not picked up, move this one line into device/google/tegu/.../BoardConfig.mk
#     (that's the canonical home for BOARD_* vars).
# ---------------------------------------------------------------------------

# --- 1. init service .rc (copy-file is fine; no +x needed for a .rc) ----------
PRODUCT_COPY_FILES += \
    vendor/mikeos/system/init/mikedaemon.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/mikedaemon.rc

# --- 2. hardened launcher (needs +x -> prebuilt EXECUTABLE module) ------------
# Defined in vendor/mikeos/system/Android.mk (BUILD_PREBUILT, EXECUTABLES ->
# /system/bin, installed 0755). PRODUCT_COPY_FILES could NOT set +x, hence a
# module. This is the daemon-as-system launcher.
PRODUCT_PACKAGES += \
    mikeos-daemon

# --- 3. sepolicy: add the mikedaemon domain to the vendor sepolicy build ------
BOARD_VENDOR_SEPOLICY_DIRS += vendor/mikeos/system/sepolicy
