# =============================================================================
# MikeOS daemon RUNTIME payload — install rule (daemon-as-system, Part A / the
# runtime-packaging follow-up, now DONE).
#
# Bakes the self-contained, Termux-FREE daemon runtime into the ROM as a single
# compressed payload on the PRODUCT partition:
#
#   vendor/mikeos/runtime/mikeos-runtime.tar.gz  ->  /product/mikeos/mikeos-runtime.tar.gz
#
# The payload is a relocatable bundle (extracted from the proven-working Termux
# runtime on the Note10, then validated running relocated from
# /data/mikeos/runtime with a Termux-free env — see
# mikedaemon/deploy/RELOCATED-RUNTIME.md). Layout inside the tar:
#     bin/    node postgres initdb pg_ctl psql pg_config pg_isready createdb
#             createuser pg_controldata redis-server redis-cli (+ redis symlinks)
#     lib/    all transitively-needed .so (libc++_shared, libicu*, libssl/crypto,
#             libpq, libreadline, libsqlite3, libxml2, libz, libffi, libcares,
#             libandroid-*, libncursesw, libiconv) + lib/postgresql/ extensions
#     share/postgresql/   postgres support files (located ../share relative to bin)
#     daemon/ dist/ (dns-fix.js line 2 intact) + node_modules + package.json
#
# On first boot the init service (init/mikedaemon.rc `on post-fs-data`) and the
# launcher (bin/mikeos-daemon) extract it ONCE to /data/mikeos/runtime (writable,
# world-rX so the datastore uid can exec the binaries), guarded by a
# /data/mikeos/runtime/.extracted marker. There is NO Termux dependency.
#
# PARTITION: /product/mikeos is on the product partition (allowed by tegu's
# PRODUCT_ARTIFACT_PATH_REQUIREMENT). It must NOT go to /system/*.
#
# SIZE: the payload is large (the runtime — Node + Postgres + Redis + node_modules
# ~ a few hundred MB compressed to ~130-180 MB). This is expected; it IS the OS
# service runtime. Kept as a product blob, read-only.
#
# Inherited from config/common.mk alongside system-daemon.mk. Kept separate so
# the runtime bake can be toggled independently of the init-service wiring.
# =============================================================================

PRODUCT_COPY_FILES += \
    vendor/mikeos/runtime/mikeos-runtime.tar.gz:$(TARGET_COPY_OUT_PRODUCT)/mikeos/mikeos-runtime.tar.gz
