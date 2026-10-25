#!/bin/sh
set -eu

# Runs offline at install time. Upstream ships the Linux build as a gzip
# tarball with one version-stamped directory, openwork-linux-x64-<ver>, holding
# a standard electron-builder tree: the openwork Chromium binary, resources,
# and the bundled OpenCode sidecars. That directory is renamed to the stable
# path the wrapper execs, /app/extra/openwork, so a later pin refresh does not
# have to edit the wrapper. The contents stay as shipped.
#
# The desktop file, icon and AppStream metainfo are installed by the manifest
# at build time. extra-data is fetched later, on the user's machine.

extra_root="${EXTRA_ROOT:-/app/extra}"
cd "$extra_root"

[ -f openwork.tar.gz ] || { echo "missing extra-data: openwork.tar.gz" >&2; exit 1; }

rm -rf stage openwork
mkdir stage
# --no-same-owner: a system install runs apply_extra as root with every
# capability dropped, so restoring the archive's uid/gid aborts the unpack.
bsdtar --no-same-owner -xf openwork.tar.gz -C stage

top="$(cd stage && ls -1 | head -n1)"
[ -n "$top" ] && [ -d "stage/$top" ] \
    || { echo "no top-level directory in tarball" >&2; exit 1; }
[ -x "stage/$top/openwork" ] \
    || { echo "openwork binary not found in tarball" >&2; exit 1; }

mv "stage/$top" openwork
rm -rf stage openwork.tar.gz
[ -x openwork/openwork ] || { echo "openwork binary missing after stage" >&2; exit 1; }
