#!/usr/bin/env bash
#
# generate-keys.sh — generate the MikeOS ROM release signing keys.
#
# Run ONCE, inside the build container, from the source root (SRC_ROOT). It
# produces the standard AOSP signing key set used by sign_target_files_apks to
# re-sign a `user`/release build so it is not shipped with the public AOSP
# test-keys. KEEP THE OUTPUT SECRET AND BACKED UP — losing the release key means
# you can never OTA-update a device that installed a build signed with it.
#
# Output: $KEYDIR/{releasekey,platform,shared,media,networkstack}.{pk8,x509.pem}
#
# NOTE: these platform keys sign the OS/framework only. They do NOT re-sign the
# preinstalled MikeOS APKs — those stay PRESIGNED (their store signatures) so
# App Store OTA updates keep working. See scripts/fetch-apps.sh.
#
# Usage:
#   SRC_ROOT=/srv/src KEYDIR=/srv/keys/mikeos ./generate-keys.sh
#
# KNOWN-UNVERIFIED (see README): make_key path + subject conventions. On
# lineage-23.2 the helper is development/tools/make_key. networkstack uses its
# own module cert; some trees also want a `sdk_sandbox` / `bluetooth` key on
# newer Android — if the sign step later complains about a missing cert, add it
# here with the same one-liner.

set -euo pipefail

SRC_ROOT="${SRC_ROOT:-/srv/src}"
KEYDIR="${KEYDIR:-${SRC_ROOT}/vendor/mikeos-keys}"   # keep OUT of the git tree!
MAKE_KEY="${SRC_ROOT}/development/tools/make_key"

# Certificate subject (DN). Edit to taste; must be a valid openssl subject.
SUBJECT='/C=SE/ST=Norrbotten/L=Kittelfjall/O=MikeOS/OU=MikeOS/CN=MikeOS/emailAddress=mikaelwestoo@gmail.com'

mkdir -p "${KEYDIR}"

if [ ! -x "${MAKE_KEY}" ]; then
  echo "ERROR: make_key not found/executable at ${MAKE_KEY}" >&2
  echo "       (it lives in the AOSP tree at development/tools/make_key)" >&2
  exit 1
fi

# make_key prompts for a password on stdin; we use an EMPTY password (press
# enter). An empty password is the AOSP default and is what sign_target_files
# expects unless you pass -p. Feed a blank line to keep it non-interactive.
# To use a passphrase instead, replace the `echo | ` with your own and pass
# `-p` to sign_target_files_apks in sign-tegu.sh, plus store the passphrase in
# a file readable only by the build user.
gen() {
  local name="$1"
  if [ -f "${KEYDIR}/${name}.pk8" ]; then
    echo "  ${name}: already exists, skipping"
    return
  fi
  echo "  ${name}: generating"
  # make_key <output-basename> <subject>
  echo | "${MAKE_KEY}" "${KEYDIR}/${name}" "${SUBJECT}"
}

echo "==> Generating MikeOS ROM signing keys in ${KEYDIR}"
gen releasekey     # signs release APKs / the default cert
gen platform       # apps sharing the system UID / signature perms
gen shared         # home/contacts shared UID
gen media          # media/download provider

# networkstack has its own module signature; conventionally same subject.
gen networkstack

echo "==> Done. Keys in ${KEYDIR}"
echo "    BACK THESE UP OFFLINE. Point sign-tegu.sh at KEYDIR=${KEYDIR}."
echo "    NEVER commit this directory to git."
