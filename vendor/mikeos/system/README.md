# MikeOS daemon-as-system (ROM overlay, Milestone 3.2 / Part A)

**Init-service + launcher: PENDING validation on the next ROM build.**
**Runtime: BAKED and PROVEN — the Node+Postgres+Redis+daemon runtime was extracted from
the working Note10 Termux install, relocated to `/data/mikeos/runtime`, and verified running
there with a Termux-FREE env** (see `## Runtime (baked, PROVEN)` below and
`mikedaemon/deploy/RELOCATED-RUNTIME.md`). Every non-obvious build assumption is flagged
inline and collected under **KNOWN-UNVERIFIED**. Design reference:
`mikeos-architecture/docs/DAEMON-AS-SYSTEM.md` (Part A).

## What this is

This replaces the fragile launch of the on-device MikeOS daemon — a Magisk
`service.d` **bash loop** running `start-daemon.sh` — with a real **Android `init`
service** baked into the ROM. `init` starts the daemon at boot, **supervises** it,
**restarts it on crash**, and **confines** it with sepolicy. The daemon is the brain
every MikeOS app depends on (`https://127.0.0.1:7743`), so it should be a first-class
system service, not a userspace script.

The concrete bug this kills: the daemon's Redis was launched with a relative
`dir ./` and no cwd guarantee; under the Magisk supervisor cwd was `/` (read-only),
so Redis bgsave failed and (with `stop-writes-on-bgsave-error yes`) Redis refused all
writes, degrading the whole daemon after every reboot. Here the data dirs are
**absolute** (`/data/mikeos/**`) and cwd-independent — the bug is impossible by
construction.

## Files

| File | Installs to | Purpose |
|------|-------------|---------|
| `init/mikedaemon.rc` | `/vendor/etc/init/mikedaemon.rc` | init service `mikeos-daemon` (class main, root, seclabel, oom_score_adjust -800, auto-restart) + `on post-fs-data` that `mkdir`s `/data/mikeos/{runtime,pg,redis,daemon,run}`, **extracts the baked runtime payload once**, then `start`s it. |
| `bin/mikeos-daemon` | `/product/bin/mikeos-daemon` (0755) | Hardened POSIX-sh launcher: **extracts the baked runtime on first boot if missing**, sets absolute Termux-free HOME/TMPDIR/PATH/LD_LIBRARY_PATH, ensures data dirs, starts Postgres (`-D /data/mikeos/pg` on 5433, initdb + createdb once) + Redis (`--dir /data/mikeos/redis --stop-writes-on-bgsave-error no`) as a datastore uid, then `exec`s `node dist/index.js` in the **foreground** so init owns its pid. |
| `runtime.mk` | — | `PRODUCT_COPY_FILES` the **baked runtime payload** `runtime/mikeos-runtime.tar.gz` → `/product/mikeos/mikeos-runtime.tar.gz`. |
| `../runtime/mikeos-runtime.tar.gz` | `/product/mikeos/mikeos-runtime.tar.gz` | The self-contained, Termux-FREE runtime bundle (node/postgres/redis binaries + all needed .so + postgres share/ + the daemon dist/+node_modules). Extracted to `/data/mikeos/runtime` on first boot. |
| `sepolicy/mikedaemon.te` | `BOARD_VENDOR_SEPOLICY_DIRS` | First-draft `mikedaemon` domain — **permissive-to-start**, audit-and-tighten. |
| `sepolicy/file_contexts` | (same) | Labels `/product/bin/mikeos-daemon` → `mikedaemon_exec`, `/data/mikeos(/.*)?` → `mikeos_data_file`. |
| `Android.mk` | — | `BUILD_PREBUILT` EXECUTABLES module `mikeos-daemon` (installs **executable** to `/product/bin` — `PRODUCT_COPY_FILES` can't set +x). |
| `system-daemon.mk` | — | Install rules: copies the `.rc`, pulls in the launcher module, adds the sepolicy dir. Kept **separate** so the whole layer toggles with one line. |

**PARTITIONS — no `/system/*`.** tegu (Pixel) enforces `PRODUCT_ARTIFACT_PATH_REQUIREMENT`:
an overlay artifact under `/system/*` fails the build (`artifact_path_requirements.mk error`).
So the launcher installs to **`/product/bin`** (not `/system/bin`) and the payload to
**`/product/mikeos/`**; only the init `.rc` goes to `/vendor/etc/init` (allowed, auto-imported).

## How it wires into the build

`vendor/mikeos/config/common.mk` inherits two layers:

```make
$(call inherit-product-if-exists, vendor/mikeos/system/system-daemon.mk)  # init .rc + launcher + sepolicy
$(call inherit-product-if-exists, vendor/mikeos/system/runtime.mk)         # the runtime payload
```

`system-daemon.mk`:
- `PRODUCT_COPY_FILES +=` the init `.rc` → `$(TARGET_COPY_OUT_VENDOR)/etc/init/mikedaemon.rc`
- `PRODUCT_PACKAGES += mikeos-daemon` (the prebuilt EXECUTABLE launcher → `/product/bin`)
- `BOARD_VENDOR_SEPOLICY_DIRS += vendor/mikeos/system/sepolicy`

`runtime.mk`:
- `PRODUCT_COPY_FILES +=` `runtime/mikeos-runtime.tar.gz` → `$(TARGET_COPY_OUT_PRODUCT)/mikeos/mikeos-runtime.tar.gz`

To disable the entire daemon-as-system layer, comment out those `inherit` lines.

## Runtime (baked, PROVEN)

The runtime is **not** built from source and does **not** need Termux. It was extracted from
the proven-working Termux install on the Note10 (`R58N4101P2V`) and relocated to a
Termux-independent path. Bundle layout (inside `mikeos-runtime.tar.gz`, extracted to
`/data/mikeos/runtime`):

```
bin/    node postgres initdb pg_ctl psql pg_config pg_isready createdb createuser
        pg_controldata redis-server redis-cli (+ redis-check-* symlinks)
lib/    libc++_shared libicu{data,i18n,uc}.78 libssl/libcrypto.3 libpq libreadline.8
        libsqlite3 libxml2.16 libz.1 libffi libcares libncursesw.6 libiconv
        libandroid-{execinfo,glob,shmem,support}   + lib/postgresql/ (45 extensions)
share/postgresql/   postgres support files (located ../share relative to the binary)
daemon/ dist/ (dns-fix.js is line 2 of index.js) + node_modules + package.json
```

Transitive `.so` deps were resolved with `readelf -d` over every binary. `libc.so`/`libm.so`/
`libdl.so`/`liblog.so` are Android bionic (satisfied by `/system/lib64` via the system
`linker64`, which every Termux binary already requests as its interpreter). Binaries + libs
are stripped and world-`rX` so the non-root datastore uid can exec them.

**PROVEN on-device (Note10), relocated from `/data/mikeos/runtime`, Termux-free env**
(`PATH=/data/mikeos/runtime/bin:/system/bin`, `LD_LIBRARY_PATH=/data/mikeos/runtime/lib:/system/lib64`,
no Termux profile) — full commands/outputs in `mikedaemon/deploy/RELOCATED-RUNTIME.md`:
- `node --version` → v26.4.0; `redis-server --version` → 8.8.0; `postgres --version` → 18.2
- redis: started `--dir /data/mikeos/redistest`; `redis-cli ping` → PONG; set/get roundtrip OK
- postgres: `initdb` completes (share/ found relative to the binary); serves `SELECT version()`
  → "PostgreSQL 18.2 on aarch64-unknown-linux-android"; `createdb mikedaemon` OK
- daemon: relocated `node dist/index.js` boots — `[dns-fix] c-ares lookup installed`,
  config loaded, auth token ready, **`✓ Connected to PostgreSQL`** (relocated node → relocated pg)

## First-boot extraction

`init/mikedaemon.rc` `on post-fs-data` (and the launcher, belt-and-suspenders) runs, once,
guarded by a `/data/mikeos/runtime/.extracted` marker:
`tar -xzf /product/mikeos/mikeos-runtime.tar.gz -C /data/mikeos/runtime` then `chmod -R a+rX`.
`toybox tar` (in `/system/bin`) handles gzip. `.tar.gz` (not `.zst`) is used because zstd may
not be in the base image; gzip/toybox always is.

## Supervision model

```
init (post-fs-data)
  └─ mkdir /data/mikeos/{runtime,pg,redis,daemon,run}  (absolute, writable)
  └─ extract /product/mikeos/mikeos-runtime.tar.gz -> /data/mikeos/runtime  (once)
  └─ start mikeos-daemon               (class main, seclabel u:r:mikedaemon:s0)
        └─ /product/bin/mikeos-daemon  (launcher, root)
             ├─ (extract runtime if still missing — belt-and-suspenders)
             ├─ start Postgres  -D /data/mikeos/pg  (initdb+createdb once, as datastore uid)
             ├─ start Redis     --dir /data/mikeos/redis --stop-writes-on-bgsave-error no
             └─ exec node dist/index.js   ← init supervises THIS pid
                    (on exit → init restarts the service → re-ensures pg/redis)
```

Single-supervisor launcher (the design's recommended starting point). Splitting into
three ordered services (`mikeos-postgres` → `mikeos-redis` → `mikeos-daemon`) is a
later option if needed.

## Runtime packaging — DONE (was the follow-up)

The runtime is now **baked natively** (Termux-free), replacing the previous Termux-path
default. `MIKEOS_RUNTIME=/data/mikeos/runtime`, extracted on first boot from the product
payload `/product/mikeos/mikeos-runtime.tar.gz` (see `## Runtime (baked, PROVEN)` above).
Postgres + Redis run as a datastore uid (`MIKEOS_PG_UID`, default 9997) via `su` — they
refuse root; once a dedicated system uid + sepolicy domains land, the `su` step can be
dropped. Node runs foreground as the init-supervised pid.

The **DoH shim stays**: `dist/index.js` line 2 must remain `require('./dns-fix.js')`
(Android netd DNS isn't reachable from Node). The launcher never touches `dist/`.

## KNOWN-UNVERIFIED (for the next build to resolve)

1. **init seclabel / domain** — `seclabel u:r:mikedaemon:s0` only works once the
   sepolicy compiles and the launcher is labeled `mikedaemon_exec`. If the domain is
   missing/mislabeled, init won't start the service. Verify on first boot.
2. **sepolicy denials** — the `.te` is **permissive** on purpose. Collect avc denials
   (`dmesg | grep avc`, `logcat | grep avc`, `audit2allow`), fold real allows in, then
   **delete `permissive mikedaemon;`** so it becomes enforcing. Do not ship permissive.
3. **sepolicy macro availability** — `init_daemon_domain`, `net_domain`, and the
   `*_perms` macros must exist in this LineageOS 23.2 / Android 16 sepolicy. If a macro
   is undefined the policy won't compile — replace with the raw `allow` it expands to.
4. **Runtime path** — defaults to Termux (`/data/data/com.termux/files`). If the device
   has no Termux, or the runtime is baked, override `MIKEOS_RUNTIME` (and drop the `su`
   branch). Also the **datastore uid** (`10151`) is Termux-specific.
5. **Launcher as prebuilt vs copy-file** — shipped as a `BUILD_PREBUILT` EXECUTABLES
   module so it installs **+x** (copy-files can't). A Soong `sh_binary` in `Android.bp`
   would be equally valid; confirm the module builds and lands at `/product/bin`.
6. **TARGET_COPY_OUT_* partitions** — `.rc` → vendor `etc/init`; launcher + payload →
   **product** (`/product/bin`, `/product/mikeos`) to satisfy tegu's
   PRODUCT_ARTIFACT_PATH_REQUIREMENT (no overlay artifact on `/system/*`). Confirm the
   `.rc` is auto-imported and the launcher is executable on first boot; the file_contexts /
   `.rc` service path already match `/product/bin/mikeos-daemon`.
7. **BOARD_VENDOR_SEPOLICY_DIRS from a product .mk** — works in current AOSP/LineageOS;
   if not picked up, move that line to `device/google/tegu/.../BoardConfig.mk`.
8. **Postgres/Redis domains** — today they run in the datastore uid's domain (via `su`),
   not `mikedaemon`. Once the runtime is baked and run directly, give them their own
   domains or run them within `mikedaemon`.
9. **Loopback TLS port 7743** — allowed via generic `node_bind`; a typed `portcon` may
   be required. Add one if denials show it.
10. **init `disabled` + explicit `start`** — the service is `disabled` and started from
    `on post-fs-data` after the mkdir, to avoid racing dir creation on first boot.
    Confirm this vs. FBE (file-based-encryption) unlock ordering on the device.
