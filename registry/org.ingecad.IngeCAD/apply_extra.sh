#!/bin/sh
set -eu

# Runs offline at install time inside org.freedesktop.Platform. Upstream
# publishes the official Linux build as a .tar.gz with one version-stamped
# top directory (IngeCAD-<version>/): the launcher, a sibling _internal/
# tree, the icon and a desktop file. The bytes are unpacked unmodified.
#
# The desktop entry, icon, MIME definition and AppStream metainfo are shipped
# by the manifest at build time. extra-data is fetched later, on the user's
# machine, so anything Flatpak must export cannot come from here.

extra_root="${EXTRA_ROOT:-/app/extra}"
cd "$extra_root"

archive=ingecad.tar.gz
[ -f "$archive" ] || { echo "missing extra-data: $archive" >&2; exit 1; }

# --no-same-owner: the tarball records a non-root owner (uid 1001 on 0.6.4),
# and on a system-wide install Flatpak runs apply_extra as root with every
# capability dropped, so restoring that owner fails and aborts the unpack.
tar --no-same-owner -xzf "$archive"

app_dir="$(find . -maxdepth 1 -type d -name 'IngeCAD-*' | sort | head -n1)"
[ -n "$app_dir" ] || { echo "no IngeCAD-* directory in tarball" >&2; exit 1; }

rm -rf ingecad
mv "$app_dir" ingecad

desktop="$(find ingecad -maxdepth 1 -name '*.desktop' -print -quit)"
[ -n "$desktop" ] || { echo "no desktop file in the tarball" >&2; exit 1; }
exec_line="$(sed -n 's/^Exec=//p' "$desktop" | head -n 1)"
bin="${exec_line%% *}"
case "$bin" in
    /*) launcher="$bin" ;;
    *) launcher="ingecad/$bin" ;;
esac
[ -n "$bin" ] && [ -x "$launcher" ] || { echo "launcher from Exec= missing after unpack: '$exec_line'" >&2; exit 1; }
[ -d ingecad/_internal ] || { echo "_internal directory missing after unpack" >&2; exit 1; }

rm -f "$archive"
