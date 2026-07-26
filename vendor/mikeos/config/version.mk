# MikeOS ROM — version / channel system properties.
#
# Read on-device via `getprop ro.mikeos.version`. Apps and the daemon can key
# behaviour off these. Bump ro.mikeos.version on each ROM release.

PRODUCT_PROPERTY_OVERRIDES += \
    ro.mikeos.version=1.0-tegu \
    ro.mikeos.channel=stable \
    ro.mikeos.device=tegu

# Optional: a human build stamp. The build system already stamps
# ro.build.fingerprint; this is just a MikeOS-namespaced convenience.
# Uncomment to embed the wall-clock build date:
# PRODUCT_PROPERTY_OVERRIDES += ro.mikeos.build.date=$(shell date -u +%Y%m%d)
