# MikeOS ROM — common product configuration (the MikeOS overlay payload).
#
# Included by products/mikeos_tegu.mk. This is what turns a plain de-Googled
# LineageOS build into MikeOS: it preinstalls the MikeOS app fleet, sets the
# MikeOS boot animation, wires the framework overlay that makes MikeOS Home the
# default launcher, and stamps the ro.mikeos.* version props.
#
# ------------------------------------------------------------------------------
# NO GOOGLE APPS. LineageOS 23.2 is already de-Googled (no GApps, no Play, no
# Google Search, no Pixel Launcher). This overlay must NEVER add GApps or any
# Google-proprietary user app. The only Google bits in the build are the tegu
# hardware blobs (graphics/modem/etc.) that come from TheMuppets — those are
# firmware, not GApps. Do not add opengapps/MindTheGapps here.
# ------------------------------------------------------------------------------

# --- Version / channel props --------------------------------------------------
$(call inherit-product, vendor/mikeos/config/version.mk)

# --- Framework overlay: default launcher = MikeOS Home ------------------------
# Applies vendor/mikeos/overlay/** (currently the config_defaultHome override).
# PRODUCT_PACKAGE_OVERLAYS is merged for all products; the value overrides the
# framework default so RoleManager assigns HOME to com.mikeos.launcher with no
# first-boot chooser. (DEVICE_PACKAGE_OVERLAYS would also work; product-scoped
# is fine here since the overlay is MikeOS-wide, not tegu-specific.)
PRODUCT_PACKAGE_OVERLAYS += vendor/mikeos/overlay

# --- Boot animation -----------------------------------------------------------
# "Michael Westoo from the sky", 720x1600. Lands on product/media/bootanimation.zip.
#
# NOTE: do NOT install this via PRODUCT_COPY_FILES. LineageOS' own soong module
# vendor/lineage/bootanimation (prebuilt_media "bootanimation.zip",
# product_specific) already owns the install rule for that path — a second rule
# makes kati fail with "overriding commands for target ... bootanimation.zip".
# Instead we feed our prebuilt through Lineage's module by setting
# TARGET_BOOTANIMATION at board-config time (see device/google/tegu/tegu/
# BoardConfig.mk); BoardConfigSoong.mk turns that into
# soong_config_set lineage_bootanimation.prebuilt_file, so the module copies our
# zip. Single install rule, MikeOS branding still wins. See BUILD-FIXES-tegu.md.

# --- MikeOS app fleet (prebuilt APKs) -----------------------------------------
# Module names are defined in vendor/mikeos/prebuilt/apps/Android.mk and are
# AUTO-GENERATED together with this list by scripts/fetch-apps.sh. If the app
# set changes, re-run that script and update this list to match its printed
# "module names" output.
#
# MikeHome (com.mikeos.launcher) and MikeSetup (com.mikeos.setup) are the two
# privileged apps (priv-app) — the default launcher and the Setup Wizard.
PRODUCT_PACKAGES += \
    MikeHome \
    MikeSetup \
    MikeAi \
    MikeApps \
    MikeBody \
    MikeBrief \
    MikeBrowser \
    MikeCamera \
    MikeChat \
    MikeDevices \
    MikeFiles \
    MikeGps \
    MikeGuide \
    MikeLens \
    MikeLingo \
    MikeLocal \
    MikeMail \
    MikeMaps \
    MikeMind \
    MikeMobile \
    MikeNews \
    MikePay \
    MikePeople \
    MikePhotos \
    MikeProducts \
    MikeRecipes \
    MikeShopping \
    MikeSound \
    MikeSpace \
    MikeStoryteller \
    MikeText \
    MikeTime \
    MikeVideo \
    MikeVoice \
    MikeWifi

# --- Optional wallpaper -------------------------------------------------------
# If a default MikeOS wallpaper is added at vendor/mikeos/prebuilt/media/
# mikeos_wallpaper.png, uncomment to ship it. Left off for now (trivial to add;
# MikeOS Home may set its own wallpaper anyway).
# PRODUCT_COPY_FILES += \
#     vendor/mikeos/prebuilt/media/mikeos_wallpaper.png:$(TARGET_COPY_OUT_PRODUCT)/media/mikeos_wallpaper.png

# --- Milestone 3.2 (DEFERRED): daemon-as-system -------------------------------
# The on-device MikeOS daemon (Node + Postgres + Redis + mikedaemon as an init
# service, sepolicy, DoH shim) is NOT part of this milestone. It needs iterative
# on-device bring-up. In the interim the existing Termux/Magisk daemon runs fine
# on this ROM. When 3.2 lands, its packages/init.rc/sepolicy get added here.
