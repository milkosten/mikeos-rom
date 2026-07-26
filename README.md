# mikeos-rom

**The MikeOS product overlay + build system.** It turns a de-Googled
**LineageOS 23.2** (Android 16) checkout into the **MikeOS ROM** for the
**Pixel 9a** (codename **`tegu`**).

This repo is an AOSP `vendor/` tree (`vendor/mikeos`), a repo local manifest,
build/sign scripts, and this runbook. It does **not** contain the OS sources —
those are synced separately from LineageOS.

> Status: **first-draft overlay, pending on-device build-iteration.** The
> makefiles are best-effort-correct AOSP. Where a choice needs a real build to
> confirm, the most-likely-correct option is implemented and the assumption is
> flagged inline and in **[KNOWN-UNVERIFIED](#known-unverified--needs-build-iteration)**
> below. Nothing here has been compiled yet.

---

## What MikeOS ROM is

LineageOS 23.2 is already de-Googled: no GApps, no Play Services, no Google
Search, no Pixel Launcher — it ships the **Trebuchet** launcher. MikeOS ROM
layers a product overlay on top that:

- **preinstalls the MikeOS app fleet** (35 `com.mikeos.*` apps) from the MikeOS
  App Store, as PRESIGNED prebuilts;
- makes **MikeOS Home** (`com.mikeos.launcher`) the **default launcher** via a
  framework `config_defaultHome` overlay (Trebuchet stays installed but
  non-default → no first-boot launcher chooser);
- preinstalls the **Setup Wizard** (`com.mikeos.setup`) as a privileged app;
- ships the **MikeOS boot animation** ("Michael Westoo from the sky");
- stamps `ro.mikeos.*` version props.

It adds **no Google apps.** The only Google-proprietary bits are the tegu
hardware **blobs** (graphics/modem/camera HAL) — firmware, not GApps.

### Milestone scope

- **Milestone 3.1 (this repo):** de-Googled Lineage 23.2 + MikeOS apps
  preinstalled + MikeOS Home default + boot cinematic + Setup Wizard
  preinstalled → a **bootable MikeOS experience**.
- **Milestone 3.2 (DEFERRED):** *daemon-as-system* — Node + Postgres + Redis +
  `mikedaemon` as an init service, with sepolicy and the DoH shim baked into the
  ROM. Deferred because it needs iterative on-device bring-up. In the interim
  the existing **Termux/Magisk daemon runs fine on this ROM**, so app-agents
  still reach `https://127.0.0.1:7743`.

---

## Repo layout

```
README.md                      # this file — what it is + full build runbook
CLAUDE.md                      # working notes for future sessions
local_manifests/mikeos.xml     # adds TheMuppets google vendor blobs for tegu
vendor/mikeos/
  config/
    common.mk                  # MikeOS product config: apps, bootanim, default-home overlay
    version.mk                 # ro.mikeos.* props
  products/
    AndroidProducts.mk         # registers mikeos_tegu + COMMON_LUNCH_CHOICES
    mikeos_tegu.mk             # inherits lineage_tegu + common.mk
  prebuilt/
    apps/
      Android.mk               # BUILD_PREBUILT module per APK (AUTO-GENERATED)
      com.mikeos.*.apk         # 35 MikeOS APKs (the product payload)
    media/
      bootanimation.zip        # MikeOS boot cinematic (720x1600)
  overlay/
    frameworks/base/core/res/res/values/config.xml   # config_defaultHome -> MikeOS Home
scripts/
  fetch-apps.sh                # (re)download APKs + regenerate prebuilt Android.mk
  build-tegu.sh                # breakfast tegu; brunch mikeos_tegu (in the container)
  sign-tegu.sh                 # sign target-files -> flashable zip
  keys/generate-keys.sh        # generate release signing keys
```

---

## Build runbook

All of this runs **in the build container** (a source sync of LineageOS 23.2 is
assumed running/complete separately). `SRC_ROOT` below is the source root, e.g.
`/srv/src`.

### 1. Init + sync LineageOS 23.2

```bash
mkdir -p /srv/src && cd /srv/src
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2

# Add the MikeOS local manifest (TheMuppets google blobs for tegu):
mkdir -p .repo/local_manifests
cp /path/to/mikeos-rom/local_manifests/mikeos.xml .repo/local_manifests/mikeos.xml

repo sync -c -j"$(nproc)"      # long
```

### 2. Drop the MikeOS overlay into the tree

`vendor/mikeos` is **not** a repo project (so `repo sync` never clobbers it) —
clone or symlink this repo's `vendor/mikeos` into place:

```bash
# clone:
git clone <mikeos-rom-url> /srv/mikeos-rom
ln -s /srv/mikeos-rom/vendor/mikeos /srv/src/vendor/mikeos
# (or copy: cp -r /srv/mikeos-rom/vendor/mikeos /srv/src/vendor/mikeos)
```

### 3. Fetch device trees + blobs

```bash
cd /srv/src
source build/envsetup.sh
breakfast tegu          # roomservice pulls android_device_google_tegu + deps
```

Blobs (`vendor/google/tegu`) come via **TheMuppets** (from the local manifest in
step 1). Alternatively, extract from a stock image:

```bash
cd device/google/tegu && ./extract-files.sh <stock-image-or-adb>
```

### 4. Build

```bash
cd /srv/src
SRC_ROOT=/srv/src VARIANT=userdebug /srv/mikeos-rom/scripts/build-tegu.sh
# -> out/target/product/tegu/*.zip  (dev build, test-keys — do not ship)
```

### 5. Sign a release build (for distribution)

```bash
SRC_ROOT=/srv/src KEYDIR=/srv/keys/mikeos /srv/mikeos-rom/scripts/keys/generate-keys.sh   # once
SRC_ROOT=/srv/src KEYDIR=/srv/keys/mikeos VARIANT=user /srv/mikeos-rom/scripts/sign-tegu.sh
# -> out/dist/mikeos_tegu-ota-signed.zip
```

### 6. Flash (Lineage recovery)

```bash
# Boot tegu into Lineage recovery, then:
adb sideload out/dist/mikeos_tegu-ota-signed.zip
```

### Refreshing the preinstalled apps

Re-run the fetcher anytime (host or container) to pull the latest store APKs and
regenerate the prebuilt module list; then rebuild:

```bash
/path/to/mikeos-rom/scripts/fetch-apps.sh
```

If the **app set** changes (added/removed packages), also update the
`PRODUCT_PACKAGES` list in `vendor/mikeos/config/common.mk` to match the module
names the script prints.

---

## KNOWN-UNVERIFIED — needs build-iteration

Check these first when the build errors. Each is implemented as the
most-likely-correct option and flagged inline in the relevant file.

1. **`config_defaultHome` resource name/type** (`overlay/.../config.xml`).
   Assumed a `<string>` `config_defaultHome` = `"pkg/cls"`. Verify against
   `frameworks/base/core/res/res/values/config.xml` on lineage-23.2 (Android
   16). An overlay naming a non-existent base resource is silently dropped by
   aapt. If Android 16 uses a different default-home mechanism, adjust
   name/type. Also **confirm the launcher's HOME Activity class** from the
   `com.mikeos.launcher` APK manifest — the override currently assumes
   `com.mikeos.launcher.MainActivity`.

2. **`lineage_tegu.mk` inherit path + product-name assertion**
   (`products/mikeos_tegu.mk`). We `inherit-product device/google/tegu/
   lineage_tegu.mk` and set `PRODUCT_NAME := mikeos_tegu`. Lineage's product
   guard may reject an unknown product name; if so, set `LINEAGE_BUILD := tegu`
   and/or `PRODUCT_RELEASE_NAME := tegu` (commented stubs are in the file), or
   inherit the device's common product pieces directly.

3. **TheMuppets path/name** (`local_manifests/mikeos.xml`). Assumed
   `TheMuppets/proprietary_vendor_google` @ `lineage-23.2`, path `vendor/google`
   (blobs under `vendor/google/tegu`). If `breakfast tegu` already wires the
   tegu vendor via roomservice, this project may be redundant/conflicting —
   remove it then. Verify exact name/path/revision.

4. **PRESIGNED update-signature caveat** (`prebuilt/apps/*`). The apps are the
   store's own-signed APKs, kept as-is via `LOCAL_CERTIFICATE := PRESIGNED`.
   This is intentional: an OTA update from the App Store must be signed with the
   **same** key as the installed app. Do **not** re-sign them with the platform
   key. (These are debug/release store APKs; PRESIGNED preserves whatever they
   are.)

5. **priv-app placement** (`prebuilt/apps/Android.mk`). MikeHome + MikeSetup go
   to `priv-app` (privileged). On Android 16, a privileged app requesting a
   `signature|privileged` permission needs a `privapp-permissions` allowlist
   entry, or the build/boot fails. If that happens, add an allowlist XML under
   `vendor/mikeos/etc/permissions` or move the app to `/app`.

6. **AVB / signed-boot** (`sign-tegu.sh`). tegu uses AVB; a signed release may
   need boot/vbmeta signed with the AVB key (`ota_from_target_files` /
   `sign_target_files_apks --avb_*` flags per the device BoardConfig). Resolve
   if flashing fails AVB verification.

7. **`make_key` path + key set** (`keys/generate-keys.sh`). Assumed
   `development/tools/make_key`, empty password, 5 standard keys. Newer Android
   may want additional module certs (e.g. `sdk_sandbox`, `bluetooth`); add them
   with the same one-liner if the sign step complains.

8. **`m dist` target-files glob** (`sign-tegu.sh`). Assumed
   `out/dist/*target_files*.zip`. Confirm the emitted filename on lineage-23.2.
