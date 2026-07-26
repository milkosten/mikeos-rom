# =============================================================================
# MikeOS daemon-as-system — install rules (Milestone 3.2 / Part A).
#
# Kept in a SEPARATE mk (inherited from config/common.mk) so this whole layer is
# easy to review and toggle: comment out the one inherit line in common.mk to
# drop daemon-as-system entirely.
#
# This wires three things into the ROM (the runtime PAYLOAD is in runtime.mk):
#   1. the init service .rc               -> /vendor/etc/init/mikedaemon.rc
#   2. the hardened launcher (executable) -> /PRODUCT/bin/mikeos-daemon
#   3. the mikedaemon sepolicy dir        -> BOARD_VENDOR_SEPOLICY_DIRS
#
# PARTITIONS: everything MikeOS lands on product/ or vendor/ — NEVER /system/*.
# tegu (Pixel) enforces PRODUCT_ARTIFACT_PATH_REQUIREMENT: an overlay artifact
# under /system/* fails the build (artifact_path_requirements.mk error). Hence
# the launcher is a /PRODUCT/bin module (Android.mk: LOCAL_PRODUCT_MODULE) and
# the payload (runtime.mk) is /product/mikeos/. The .rc -> /vendor/etc/init is
# fine (vendor partition, auto-imported).
#
# ---------------------------------------------------------------------------
# KNOWN-UNVERIFIED (resolve on the NEXT build — see README.md):
#   * The .rc goes to the VENDOR partition's etc/init (init auto-imports
#     /vendor/etc/init/*.rc); the launcher + payload go to PRODUCT. Confirm all
#     three land + the .rc is auto-imported on first boot.
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
# /PRODUCT/bin, installed 0755, LOCAL_PRODUCT_MODULE). PRODUCT_COPY_FILES could
# NOT set +x, hence a module. This is the daemon-as-system launcher.
PRODUCT_PACKAGES += \
    mikeos-daemon

# --- 3. sepolicy: add the mikedaemon domain to the vendor sepolicy build ------
BOARD_VENDOR_SEPOLICY_DIRS += vendor/mikeos/system/sepolicy
