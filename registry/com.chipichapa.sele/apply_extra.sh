#!/bin/sh
set -eu

# Offline install-time extraction of the official Electron tarball. Preserve
# the complete app tree; no app files are patched or rebuilt. The tarball has
# the executable and resources at its root, as electron-builder's tar.gz does.
extra_root="${EXTRA_ROOT:-/app/extra}"
cd "$extra_root"
[ -f sele.tar.gz ] || { echo "missing extra-data: sele.tar.gz" >&2; exit 1; }
rm -rf sele
mkdir sele
# System installs run as root with all capabilities dropped; do not chown.
tar --no-same-owner -xzf sele.tar.gz -C sele
[ -x sele/sele ] && [ -f sele/resources/app.asar ] \
    || { echo "Sele executable or resources missing from tarball" >&2; exit 1; }
rm -f sele.tar.gz
