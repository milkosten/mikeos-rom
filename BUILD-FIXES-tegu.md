# MikeOS ROM (tegu / Pixel 9a) — base-tree build fixes

Port fixes applied to base LineageOS / device-tree files to get the MikeOS
`mikeos_tegu` product to build. Documented here so they can be upstreamed into
this overlay as patches (base files are reverted by `repo sync`).

## 1. `LINEAGE_BUILD` not derived for the `mikeos_` product prefix (kernel soong vars)

**Symptom (the original blocker):**
```
error: vendor/lineage/build/soong/Android.bp:25:8: module "generated_kernel_includes":
       cmd: unknown variable '$(TARGET_KERNEL_PLATFORM_TARGET)'
error: vendor/lineage/build/soong/Android.bp:60:8: module "prebuilt_kernel_includes":
       cmd: unknown variable '$(KERNEL_BUILD_OUT_PREFIX)'
ninja: build stopped: subcommand failed.
```

**Root cause:** LineageOS's kernel-header genrule modules
(`generated_kernel_includes`, `prebuilt_kernel_includes`) reference make vars
(`TARGET_KERNEL_PLATFORM_TARGET`, `KERNEL_BUILD_OUT_PREFIX`, `TARGET_KERNEL_SOURCE`,
…) that are exported into a soong config namespace `lineageVarsPlugin` by
`vendor/lineage/config/BoardConfigSoong.mk`. That file is only reached via
`build/make/core/config.mk`:
```
ifneq ($(LINEAGE_BUILD),)
include vendor/lineage/config/BoardConfigLineage.mk   # -> BoardConfigKernel.mk + BoardConfigSoong.mk
endif
```
`LINEAGE_BUILD` is set by `check_product()` in `vendor/lineage/build/envsetup.sh`,
which only strips a `lineage_` prefix. Our product is `mikeos_tegu` (renamed from
`lineage_tegu` so `brunch` doesn't mangle the name), so `LINEAGE_BUILD` stayed
empty → `BoardConfigLineage.mk` was never included → the `lineageVarsPlugin`
namespace was never created → soong saw the `$(...)` vars as unknown → ninja
stopped in seconds.

**Fix:** teach `check_product()` to also handle the `mikeos_` prefix (sets
`LINEAGE_BUILD=tegu`, the codename all downstream Lineage logic expects). Applied
by `vendor/mikeos/scripts/patch-lineage-build-prefix.py`, invoked idempotently by
`vendor/mikeos/scripts/build-tegu.sh` every build so a `vendor/lineage` re-sync
cannot silently reintroduce the bug.

**Files touched (base):** `vendor/lineage/build/envsetup.sh` (`check_product`).

## 2. `bootanimation.zip` double-defined (kati "overriding commands")

**Symptom (surfaced after fix #1 enabled the Lineage bootanimation module):**
```
build/make/core/Makefile:148: error: overriding commands for target
  'out/target/product/tegu/product/media/bootanimation.zip',
  previously defined at out/soong/installs-mikeos_tegu.mk:98003
kati failed with: exit status 1
```

**Root cause:** LineageOS ships a soong module `vendor/lineage/bootanimation`
(`prebuilt_media` named `bootanimation.zip`, `product_specific: true`) that owns
the install rule for `product/media/bootanimation.zip`. The MikeOS overlay
installed its own bootanimation to the *same* path via `PRODUCT_COPY_FILES` → two
rules for one output → kati error. (Only appeared once fix #1 turned the Lineage
plumbing on.)

**Fix (the Lineage-sanctioned way to ship a prebuilt bootanimation):**
- Removed the conflicting `PRODUCT_COPY_FILES` line from
  `vendor/mikeos/config/common.mk` (overlay file — permanent).
- Set `TARGET_BOOTANIMATION := vendor/mikeos/prebuilt/media/bootanimation.zip`
  (guarded by a `wildcard` check) in `device/google/tegu/tegu/BoardConfig.mk`
  before `BoardConfigLineage.mk` runs. `BoardConfigSoong.mk` turns that into
  `soong_config_set lineage_bootanimation.prebuilt_file`, so the Lineage genrule
  simply copies the MikeOS zip. One install rule; MikeOS branding wins.

**Files touched:** `device/google/tegu/tegu/BoardConfig.mk` (base, guarded), and
`vendor/mikeos/config/common.mk` (overlay).

## Kernel build path (resolved)

tegu sets `TARGET_NO_KERNEL := true` (via `device/google/zumapro/BoardConfig-common.mk`)
and does NOT use Lineage's `FULL_KERNEL_BUILD` path — its kernel comes from the
device tree's own Kleaf/bazel `dist` target (`//private/devices/google/tegu:...`),
run during dependency resolution, which copies the built kernel + prebuilt `.ko`
modules into `device/google/tegu-kernels/6.1/`. So the Lineage kernel-header
genrule vars just needed to be *registered* (empty is fine) — exactly what fix #1
restores.
