# MikeOS daemon-as-system (ROM overlay, Milestone 3.2 / Part A)

**FIRST DRAFT — correct-by-convention, PENDING validation on the next ROM build.**
Nothing here has been compiled or booted yet. Every non-obvious assumption is flagged
inline and collected under **KNOWN-UNVERIFIED** below. Design reference:
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
| `init/mikedaemon.rc` | `/vendor/etc/init/mikedaemon.rc` | init service `mikeos-daemon` (class main, root, seclabel, oom_score_adjust -800, auto-restart) + `on post-fs-data` that `mkdir`s `/data/mikeos/{pg,redis,daemon,run}` then `start`s it. |
| `bin/mikeos-daemon` | `/system/bin/mikeos-daemon` (0755) | Hardened POSIX-sh launcher: sets absolute HOME/TMPDIR/PATH, ensures data dirs, starts Postgres (`-D /data/mikeos/pg`, initdb once) + Redis (`--dir /data/mikeos/redis --stop-writes-on-bgsave-error no`), then `exec`s `node dist/index.js` in the **foreground** so init owns its pid. |
| `sepolicy/mikedaemon.te` | `BOARD_VENDOR_SEPOLICY_DIRS` | First-draft `mikedaemon` domain — **permissive-to-start**, audit-and-tighten. |
| `sepolicy/file_contexts` | (same) | Labels `/system/bin/mikeos-daemon` → `mikedaemon_exec`, `/data/mikeos(/.*)?` → `mikeos_data_file`. |
| `Android.mk` | — | `BUILD_PREBUILT` EXECUTABLES module `mikeos-daemon` (so the launcher installs **executable** — `PRODUCT_COPY_FILES` can't set +x). |
| `system-daemon.mk` | — | Install rules: copies the `.rc`, pulls in the launcher module, adds the sepolicy dir. Kept **separate** so the whole layer toggles with one line. |

## How it wires into the build

`vendor/mikeos/config/common.mk` (unchanged except one additive line) inherits this layer:

```make
$(call inherit-product-if-exists, vendor/mikeos/system/system-daemon.mk)
```

`system-daemon.mk` then:
- `PRODUCT_COPY_FILES +=` the init `.rc` → `$(TARGET_COPY_OUT_VENDOR)/etc/init/mikedaemon.rc`
- `PRODUCT_PACKAGES += mikeos-daemon` (the prebuilt EXECUTABLE launcher from `Android.mk`)
- `BOARD_VENDOR_SEPOLICY_DIRS += vendor/mikeos/system/sepolicy`

To disable the entire daemon-as-system layer, comment out that single `inherit` line.

## Supervision model

```
init (post-fs-data)
  └─ mkdir /data/mikeos/{pg,redis,daemon,run}  (absolute, writable)
  └─ start mikeos-daemon               (class main, seclabel u:r:mikedaemon:s0)
        └─ /system/bin/mikeos-daemon   (launcher, root)
             ├─ start Postgres  -D /data/mikeos/pg
             ├─ start Redis     --dir /data/mikeos/redis --stop-writes-on-bgsave-error no
             └─ exec node dist/index.js   ← init supervises THIS pid
                    (on exit → init restarts the service → re-ensures pg/redis)
```

Single-supervisor launcher (the design's recommended starting point). Splitting into
three ordered services (`mikeos-postgres` → `mikeos-redis` → `mikeos-daemon`) is a
later option if needed.

## Runtime-packaging TODO (the follow-up, NOT done here)

The launcher's `MIKEOS_RUNTIME` defaults to the **current Termux path**
(`/data/data/com.termux/files`) for continuity — so on today's layered/Termux devices
the init service works immediately (Node + Postgres + Redis + the mikedaemon `dist/`
are all still under the Termux prefix, and pg/redis are still `su`'d to the Termux uid
`10151`).

The real endgame is to **bake the runtime natively** into the system/vendor image (or
lay it down as a first-boot `/data/mikeos` payload) so there is **no Termux dependency
and no `su`/uid dance**. When that lands: repoint `MIKEOS_RUNTIME`/`MIKEOS_PREFIX`/
`MIKEOS_DAEMON_DIR` at the baked locations, run pg/redis directly (dropping the `su`
branch), and pick a dedicated system uid for the datastores. **This is deliberately
out of scope for this deliverable** — the init-service + absolute-dirs hardening is
what ships now.

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
   would be equally valid; confirm the module builds and lands at `/system/bin`.
6. **TARGET_COPY_OUT_* partitions** — `.rc` → vendor `etc/init`, launcher → system
   `bin`. On a system-only device these may coincide. Confirm the `.rc` is auto-imported
   and the launcher is executable on first boot; adjust partitions + the file_contexts /
   `.rc` service path together if either must move (e.g. to `/vendor/bin`).
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
