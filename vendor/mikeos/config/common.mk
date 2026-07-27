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

# --- Remove LineageOS's launcher + setup wizard (MikeOS replaces both) ---------
# LineageOS ships Trebuchet (module Launcher3QuickStep, package com.android.launcher3)
# and its own SetupWizard (module LineageSetupWizard, "Welcome to LineageOS"). Both
# come in via the inherited lineage_tegu product. We ship our own:
#   * com.mikeos.launcher (MikeHome) is the ONLY launcher -> removing Trebuchet means
#     no "Select home app" chooser on first boot (one HOME candidate auto-holds the role).
#   * com.mikeos.setup (MikeSetup) is the setup wizard -> removing LineageSetupWizard
#     kills the "Welcome to LineageOS" flow so MikeSetup owns first boot (it declares
#     CATEGORY_SETUP_WIZARD + HOME and marks the device provisioned when done).
# PRODUCT_PACKAGES_REMOVE strips them from the product package set even though inherited.
PRODUCT_PACKAGES_REMOVE += \
    LineageSetupWizard \
    Provision

# --- MikeSetup privileged-permission allowlist --------------------------------
# MikeSetup is a /product/priv-app; it requests WRITE_SECURE_SETTINGS (to flip
# device_provisioned / user_setup_complete on completion). Android 16 fatally
# refuses a priv-app's signature|privileged permission unless it is allowlisted.
PRODUCT_COPY_FILES += \
    vendor/mikeos/etc/permissions/privapp-permissions-com.mikeos.setup.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/permissions/privapp-permissions-com.mikeos.setup.xml

# --- Default wallpaper --------------------------------------------------------
# A branded MikeOS wallpaper (violet sky + wordmark) so the home/lock background
# "says MikeOS" out of the box. Shipped as a framework resource overlay against
# com.android.internal default_wallpaper (via PRODUCT_PACKAGE_OVERLAYS above):
#   vendor/mikeos/overlay/frameworks/base/core/res/res/drawable-nodpi/default_wallpaper.png
# (Overlaying the framework default is the standard ROM way to set a stock wallpaper;
# the launcher also paints its own violet-sky + wordmark face on top.)

# --- Milestone 3.2: daemon-as-system ------------------------------------------
# The on-device MikeOS daemon (Node + Postgres + Redis + mikedaemon) is baked in
# as a real Android init service instead of the fragile Termux/Magisk bash loop:
# init supervises it, restarts it on crash, and absolute /data/mikeos data dirs
# kill the read-only-cwd Redis `dir ./` bug class. Install rules (init .rc +
# executable launcher + sepolicy) live in a SEPARATE, easy-to-toggle mk. This is
# a FIRST-DRAFT overlay to be validated on the NEXT ROM build — see
# vendor/mikeos/system/README.md for the KNOWN-UNVERIFIED list. To disable the
# whole layer, comment out the single inherit line below.
#
# RUNTIME BAKED (the packaging follow-up is DONE): the launcher now points at the
# baked, Termux-FREE runtime at /data/mikeos/runtime, extracted on first boot from
# a product-partition payload (/product/mikeos/mikeos-runtime.tar.gz). Node +
# Postgres + Redis + the mikedaemon dist/ ship in that payload — NO Termux. The
# DoH shim (dns-fix.js line 2) is unchanged. Install rules:
#   system-daemon.mk : init .rc + /product/bin launcher + sepolicy
#   runtime.mk       : the /product/mikeos/mikeos-runtime.tar.gz payload
$(call inherit-product-if-exists, vendor/mikeos/system/system-daemon.mk)
$(call inherit-product-if-exists, vendor/mikeos/system/runtime.mk)

# --- MikeOS system location provider ------------------------------------------
# com.mikeos.location is the SINGLE designated GNSS provider (DAEMON-AS-SYSTEM.md
# Part B). Preinstalled system app (via prebuilt/apps/Android.mk -> /product/app,
# so non-removable). Location is auto-granted by the default-permissions XML below
# so it feeds the daemon from first boot with NO runtime prompt. MikeGuide's old
# provider role is removed (it becomes a plain reader of GET /api/location).
PRODUCT_PACKAGES += MikeLocation
PRODUCT_COPY_FILES += \
    vendor/mikeos/etc/default-permissions/mikeos-location-default-permissions.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/default-permissions/mikeos-location-default-permissions.xml \
    vendor/mikeos/etc/default-permissions/mikeos-setup-default-permissions.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/default-permissions/mikeos-setup-default-permissions.xml
