# MikeOS ROM — product definition for tegu (Pixel 9a).
#
# MikeOS is a PRODUCT OVERLAY on top of de-Googled LineageOS 23.2 (Android 16).
# We do NOT rebuild the device from AOSP base — we inherit the fully-formed
# Lineage device product (lineage_tegu), then layer the MikeOS product config
# (apps, branding, boot animation, default-home override) on top.
#
# IMPORTANT: do NOT `inherit-product aosp_base.mk` here — that would drop all of
# Lineage's device wiring (kernel, HALs, sepolicy, blob plumbing). Inheriting
# device/google/tegu/lineage_tegu.mk is the correct base.

# --- Base: the Lineage device product -----------------------------------------
# Pulled into the tree by `breakfast tegu` (roomservice clones
# LineageOS/android_device_google_tegu @ lineage-23.2 to device/google/tegu).
$(call inherit-product, device/google/tegu/lineage_tegu.mk)

# --- MikeOS overlay: apps + branding + bootanim + default-home ----------------
# inherit-product-if-exists so a bare `breakfast tegu` (before vendor/mikeos is
# cloned in) still parses; brunch mikeos_tegu requires vendor/mikeos present.
$(call inherit-product-if-exists, vendor/mikeos/config/common.mk)

# --- Product identity ----------------------------------------------------------
# PRODUCT_DEVICE must stay `tegu` so the device makefiles, fstab, and
# TARGET_DEVICE all resolve. Only the PRODUCT_NAME changes vs lineage_tegu.
PRODUCT_NAME := mikeos_tegu
PRODUCT_DEVICE := tegu
PRODUCT_BRAND := MikeOS
PRODUCT_MODEL := MikeOS (Pixel 9a)
PRODUCT_MANUFACTURER := Google

# KNOWN-UNVERIFIED (see README "KNOWN-UNVERIFIED"): lineage_tegu.mk runs
# `PRODUCT_ENFORCE_ARTIFACT_PATH_REQUIREMENTS` and may assert on PRODUCT_NAME
# via `PRODUCT_RELEASE_NAME` / Lineage's product-name check
# (build/make/core/... "PRODUCT_NAME is not one of ..."). If brunch complains
# that mikeos_tegu is not a known Lineage product, the fix is one of:
#   * set  LINEAGE_BUILD := tegu   (some trees key branding off this), and/or
#   * set  PRODUCT_RELEASE_NAME := tegu
#   * or `inherit-product`  device/google/tegu/device.mk + lineage common
#     product pieces directly instead of lineage_tegu.mk.
# Left as-is (cleanest form) pending first build; resolve at build time.
# LINEAGE_BUILD := tegu
# PRODUCT_RELEASE_NAME := tegu
