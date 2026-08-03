# MikeOS ROM — version / channel system properties.
#
# Read on-device via `getprop ro.mikeos.version`. Apps and the daemon can key
# behaviour off these. Bump ro.mikeos.version on each ROM release.
#
# WHY /PRODUCT AND NOT /VENDOR (v37 fix):
# These MUST be PRODUCT_PRODUCT_PROPERTIES, not PRODUCT_PROPERTY_OVERRIDES.
# PRODUCT_PROPERTY_OVERRIDES lands the props in /vendor/build.prop, but the
# /vendor property domain cannot DEFINE arbitrary ro.mikeos.* names: without a
# property_contexts entry the property manager drops them, so
# `getprop ro.mikeos.version` returned EMPTY on the booted v36 device even
# though the line was present in /vendor/build.prop. Setting them from /product
# (a coredomain partition) PLUS the property_contexts entry in
# vendor/mikeos/system/sepolicy/property_contexts (labels ro.mikeos.* as
# build_prop, world-readable) makes the value actually resolve at runtime.

PRODUCT_PRODUCT_PROPERTIES += \
    ro.mikeos.version=38-tegu \
    ro.mikeos.channel=stable \
    ro.mikeos.device=tegu

# Optional: a human build stamp. The build system already stamps
# ro.build.fingerprint; this is just a MikeOS-namespaced convenience.
# Uncomment to embed the wall-clock build date:
# PRODUCT_PRODUCT_PROPERTIES += ro.mikeos.build.date=$(shell date -u +%Y%m%d)
