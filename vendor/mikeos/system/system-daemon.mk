# =============================================================================
# MikeOS daemon-as-system — install rules (Milestone 3.2 / Part A).
#
# Kept in a SEPARATE mk (inherited from config/common.mk) so this whole layer is
# easy to review and toggle: comment out the one inherit line in common.mk to
# drop daemon-as-system entirely.
#
# This wires three things into the ROM (the runtime PAYLOAD is in runtime.mk):
#   1. the init service .rc               -> /product/etc/init/mikedaemon.rc
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
# INSTALL TO /PRODUCT, NOT /VENDOR (v38 boot-auto-start fix):
#   The `on post-fs-data` block below mkdir's + chmod/chown's /data/mikeos, whose
#   file_contexts label is `mikeos_data_file` (a `core_data_file_type`). init
#   runs the built-in commands of a .rc under a subcontext keyed by the .rc's
#   partition: only /vendor and /odm get the `vendor_init` context (init source
#   subcontext.cpp: Subcontext({"/vendor","/odm"}, kVendorContext)); every other
#   partition — including /product and /system_ext — runs as `init` itself.
#   `vendor_init` is NOT a coredomain and the base vendor_init.te EXCLUDES
#   `-core_data_file_type` from its create/setattr grants, so a /vendor .rc's
#   `mkdir /data/mikeos ... <mode> <uid>` was DENIED at the setattr (chmod/chown)
#   under enforcing:
#       avc: denied { setattr } comm="init" name="mikeos"
#            scontext=u:r:vendor_init:s0 tcontext=u:object_r:mikeos_data_file:s0
#   which errored the mkdir command and ABORTED the block before `start
#   mikeos-daemon` — so the daemon never auto-started (only a manual ctl.start
#   worked). `init` (a coredomain) DOES have create+setattr on core_data_file_type
#   dirs (base init.te grants `file_type` minus app/vendor/system types — NOT
#   minus core_data_file_type). Installing the .rc to /product/etc/init makes the
#   block run as `init`, which is allowed. init auto-imports /product/etc/init/*.rc
#   exactly as it does /vendor/etc/init/*.rc, so nothing else changes.
PRODUCT_COPY_FILES += \
    vendor/mikeos/system/init/mikedaemon.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/mikedaemon.rc

# --- 2. hardened launcher (needs +x -> prebuilt EXECUTABLE module) ------------
# Defined in vendor/mikeos/system/Android.mk (BUILD_PREBUILT, EXECUTABLES ->
# /PRODUCT/bin, installed 0755, LOCAL_PRODUCT_MODULE). PRODUCT_COPY_FILES could
# NOT set +x, hence a module. This is the daemon-as-system launcher.
PRODUCT_PACKAGES += \
    mikeos-daemon

# --- 3. sepolicy: add the mikedaemon domain to the vendor sepolicy build ------
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += vendor/mikeos/system/sepolicy
