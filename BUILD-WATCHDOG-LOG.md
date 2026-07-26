# MikeOS ROM (tegu / Pixel 9a) — build watchdog log

## 2026-07-26 — SELinux `mikedaemon` neverallow failures (FINAL build blocker)

**Symptom.** The ROM built to completion except for the `precompiled_sepolicy` /
`sepolicy_neverallows` step, which failed with **7 neverallow assertion violations** on our
custom `mikedaemon` domain. `permissive mikedaemon;` does NOT exempt these — neverallows are
compile-time assertions in `system/sepolicy/private/domain.te`, not runtime denials.

### The 7 violations (from `m precompiled_sepolicy`)
1. `allow mikedaemon self:capability { dac_override }` — `dac_override` is a hard neverallow for
   any non-exempt domain (domain.te:2033).
2. `allow mikedaemon mikedaemon_exec:file { entrypoint }` (via `init_daemon_domain`) — Treble
   cross-partition entrypoint neverallow (domain.te:1237): a **vendor** domain may not entrypoint
   an exec type that isn't `vendor_file_type`; our launcher is on `/product`.
3-7. `allow mikedaemon mikeos_data_file:{dir,file,sock_file,lnk_file}` — `mikeos_data_file` was
   declared `core_data_file_type`, and a **vendor** domain may not access `core_data_file_type`
   (domain.te:1108/1132/1015).

**Root cause.** `mikedaemon` was declared as a **vendor** domain (added via
`BOARD_VENDOR_SEPOLICY_DIRS`), but everything it owns is on the **core/system side of Treble**:
the launcher is `/product/bin/mikeos-daemon` and the data tree is `/data/mikeos` (core data, not
`/data/vendor`). Treble forbids a vendor domain from entrypointing a /product exec or touching
core data. Declaring it vendor was the mistake.

### The fix (neverallow-clean; domain kept PERMISSIVE)
Made `mikedaemon` a **coredomain** built as **system_ext private** policy, and dropped the
one capability that is unconditionally banned:

- `vendor/mikeos/system/system-daemon.mk`
  `BOARD_VENDOR_SEPOLICY_DIRS` → **`SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS`**. Building the policy as
  system_ext private makes the domain a `coredomain`, which is the side of Treble its files
  actually live on.
- `vendor/mikeos/system/sepolicy/mikedaemon.te`
  - `type mikedaemon, domain;` → **`type mikedaemon, domain, coredomain;`**. As a coredomain the
    entrypoint + core-data rules are the ones that APPLY (and are satisfied), clearing violations
    2-7.
  - `type mikedaemon_exec, exec_type, file_type;` → **add `system_file_type`**. A coredomain may
    only entrypoint `system_file_type` (or postinstall) files; `/product` is system-side, so
    labelling the exec `system_file_type` is correct and clears the entrypoint neverallow.
  - `type mikeos_data_file, ... core_data_file_type;` — **kept** `core_data_file_type` (it was the
    RIGHT attribute all along, once the domain is core: a coredomain may only manage `data_file_type`
    that is `core_data_file_type`/`app_data_file_type`). `/data/mikeos` is core data.
  - `allow mikedaemon self:capability { ... dac_override };` → **dropped `dac_override`**
    (hard neverallow). Remaining caps `{ setuid setgid net_raw net_admin }` are fine. Being
    permissive, any real dac_override need will surface as an avc to fix properly (ownership/modes),
    not by re-granting the banned cap.

**Verification.** `m precompiled_sepolicy` → **`build completed successfully`**, 0 neverallow
failures. `permissive mikedaemon;` retained (enforcing is a post-boot `audit2allow` job, not done
here).

**file_contexts / init.rc / Android.mk unchanged** — the launcher stays at `/product/bin/mikeos-daemon`
and data at `/data/mikeos`; only the domain's *partition classification* in policy changed, not any
install path. No `/vendor` move was needed.

After the fix, the full `mka bacon` was relaunched detached on the build box.
