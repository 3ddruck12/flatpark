#!/bin/sh
set -eu

# Runs offline at install time inside org.freedesktop.Platform. Upstream ships
# the official Linux build as a .tar.gz with a single version-stamped top
# directory (solvecraft-<ver>-linux-<arch>/) holding bin/solvecraft,
# bin/solvecraft-cli and a share/ tree. Rename that directory to a stable path
# the wrappers exec across updates.

extra_root="${EXTRA_ROOT:-/app/extra}"
cd "$extra_root"

archive=solvecraft.tar.gz
[ -f "$archive" ] || { echo "missing extra-data: $archive" >&2; exit 1; }

# --no-same-owner: the tarball records a non-root owner (uid 1001),
# and on a system-wide install Flatpak runs apply_extra as root with every
# capability dropped, so restoring that owner fails and aborts the unpack.
tar --no-same-owner -xzf "$archive"
app_dir="$(find . -maxdepth 1 -type d -name 'solvecraft-*' | sort | head -n1)"
[ -n "$app_dir" ] || { echo "no solvecraft-* directory in tarball" >&2; exit 1; }

rm -rf solvecraft
mv "$app_dir" solvecraft

for b in solvecraft solvecraft-cli; do
  [ -x "solvecraft/bin/$b" ] || { echo "solvecraft/bin/$b not found in tarball" >&2; exit 1; }
done

rm -f "$archive"
