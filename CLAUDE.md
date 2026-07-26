# mikeos-rom — CLAUDE.md

Working notes for future sessions on the **MikeOS ROM** overlay.

## What this repo is

The **MikeOS product overlay + build kit** that turns a de-Googled **LineageOS
23.2** (Android 16) checkout into the **MikeOS ROM** for the **Pixel 9a
(`tegu`)**. It is an AOSP `vendor/mikeos` tree + repo local manifest + build/
sign scripts + runbook. It does NOT hold the OS sources (synced separately from
LineageOS on a build box).

**Read `README.md` first** — it has the full build runbook and the
`KNOWN-UNVERIFIED` list (the assumptions to check first when a build errors).

## Ground truth (do not re-derive)

- Base: **LineageOS 23.2**, already de-Googled (Trebuchet launcher, no GApps).
  **Never add GApps to this overlay.**
- Device: **tegu** = Pixel 9a. Lineage product `lineage_tegu`, path
  `device/google/tegu` (`LineageOS/android_device_google_tegu` @ `lineage-23.2`).
  Blobs from **TheMuppets/proprietary_vendor_google**.
- Our product: **`mikeos_tegu`** (inherits `lineage_tegu` + `common.mk`).
- Overlay tree path in the checkout: **`vendor/mikeos`** (cloned/symlinked in,
  NOT a repo manifest project — so `repo sync` never clobbers it).
- Apps: 35 `com.mikeos.*` packages, fetched from the App Store
  (`$APPSTORE_URL=https://mikeos-appstore.up.railway.app`, catalog `GET
  /api/apps`, download `GET /api/apps/{pkg}/download`). Two are special:
  `com.mikeos.launcher` = MikeOS Home (default launcher, priv-app),
  `com.mikeos.setup` = Setup Wizard (priv-app).

## How the pieces fit

- `products/mikeos_tegu.mk` → inherits `device/google/tegu/lineage_tegu.mk`,
  then `vendor/mikeos/config/common.mk`, then sets product identity.
- `config/common.mk` → the MikeOS payload: `PRODUCT_PACKAGES` (app modules),
  bootanim `PRODUCT_COPY_FILES`, `PRODUCT_PACKAGE_OVERLAYS += vendor/mikeos/
  overlay`, includes `version.mk`. **NO GApps.**
- `overlay/.../config.xml` → overrides `config_defaultHome` so RoleManager makes
  MikeOS Home the default (no first-boot chooser).
- `prebuilt/apps/Android.mk` → one `BUILD_PREBUILT` PRESIGNED module per APK.
  **AUTO-GENERATED** by `scripts/fetch-apps.sh` — do not hand-edit.

## Package → module-name map (stable)

`com.mikeos.launcher`→`MikeHome`, `com.mikeos.setup`→`MikeSetup`, otherwise
`com.mikeos.<x>`→`Mike<Titlecased x>` (browser→`MikeBrowser`, ai→`MikeAi`). The
map lives in `fetch-apps.sh` and must match the `PRODUCT_PACKAGES` list in
`common.mk`. If the app set changes: re-run `fetch-apps.sh`, then sync the
`common.mk` list to its printed module names.

## Signing model (important)

- **MikeOS APKs stay PRESIGNED** (their store signatures). Never re-sign them
  with the platform key — App Store OTA updates require the same signing key as
  the installed app.
- **The OS/framework** is re-signed with MikeOS release keys
  (`keys/generate-keys.sh` → `sign-tegu.sh`) for `user` builds. Keys live OUTSIDE
  the git tree (`vendor/mikeos-keys` / `/srv/keys/mikeos`). **Never commit keys.**

## Milestones

- **3.1 (done here):** bootable MikeOS experience (apps + default home + boot
  cinematic + setup wizard). First-draft, pending build-iteration.
- **3.2 (deferred):** daemon-as-system (Node+Postgres+Redis+mikedaemon as init
  service, sepolicy, DoH shim). Termux/Magisk daemon works in the interim.

## Conventions

- Push over SSH (`~/.ssh/mikeos_git_deploy`; PATs lack Contents:write). Repo is
  `milkosten/mikeos-rom` (milkosten is a USER, not an org).
- Do NOT build here or SSH to a build box — builds happen on the separate box.
  This repo is the durable, reviewable overlay kit only.
- APKs ARE committed (they're the product payload); the repo is large by design.
