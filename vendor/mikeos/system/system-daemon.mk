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
#   3. the mikedaemon sepolicy dir        -> SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS
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
#   * The sepolicy dir is added via SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS (not
#     BOARD_VENDOR_SEPOLICY_DIRS). mikedaemon is a CORE domain (its launcher is
#     on /product, its data on /data/mikeos — both core-side of Treble), so it
#     must be built as system_ext/product private policy and carry `coredomain`.
#     A VENDOR domain hit Treble neverallows (cross-partition entrypoint + no
#     access to core_data_file_type); a coredomain declared here does not.
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

# --- 3. sepolicy: add the mikedaemon domain to the system_ext private policy ---
# mikedaemon is a coredomain (see sepolicy/mikedaemon.te + the note above), so
# its policy is built as system_ext PRIVATE policy, NOT vendor policy. This is
# what makes the domain a coredomain and clears the Treble cross-partition
# neverallows (entrypoint of a /product exec + management of /data/mikeos).
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += vendor/mikeos/system/sepolicy
