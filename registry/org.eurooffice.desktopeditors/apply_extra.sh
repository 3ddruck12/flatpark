#!/bin/sh
set -eu

# The .deb unpack below is a pipeline. Enable pipefail when the runtime shell
# supports it so a failure in either bsdtar process cannot leave a partial
# installation.
# shellcheck disable=SC3040
(set -o pipefail) 2> /dev/null && set -o pipefail || true

# Runs offline at install time inside org.freedesktop.Platform. Two kinds of
# payload:
#
#   euro-office.deb          upstream's official amd64 .deb. A plain FHS tree:
#                            the editors under /opt/euro-office/euro-office
#                            (DesktopEditors, libcef, the converter, dictionaries)
#                            and the vendor launcher at /usr/bin/euro-office-euro-office.
#   libgssapi-krb5-2.deb     Debian trixie. This build's libQt6Network.so.6
#   libkrb5-3.deb            needs libgssapi_krb5.so.2 (gssapi_krb5_2_MIT), which
#   libk5crypto3.deb         neither the .deb nor the runtime ships. The other
#   libkrb5support0.deb      four packages are that library's own dependencies
#   libkeyutils1.deb         that the runtime also lacks (libcom_err and libssl
#                            are already in the runtime).
#
# The app tree is staged at /app/extra/opt and the launcher at /app/extra/usr/bin.
# The Kerberos libraries land in /app/extra/deps, a directory the wrapper puts
# on LD_LIBRARY_PATH. The desktop file, icon and AppStream metainfo are shipped
# by the manifest at *build* time — extra-data is fetched later on the user's
# machine, so anything Flatpak must export cannot come from here.

extra_root="${EXTRA_ROOT:-/app/extra}"
cd "$extra_root"

for f in euro-office.deb libgssapi-krb5-2.deb libkrb5-3.deb libk5crypto3.deb \
         libkrb5support0.deb libkeyutils1.deb; do
    [ -f "$f" ] || { echo "missing extra-data: $f" >&2; exit 1; }
done

# The Platform runtime has no ar/dpkg, but bsdtar (libarchive) reads a .deb ar
# container directly; pipe its data member into a second bsdtar to unpack the
# tree (the inner data.tar compression is auto-detected).
# --no-same-owner: on a system-wide install Flatpak runs apply_extra as root
# with every capability dropped, so restoring an archive's recorded uid/gid
# fails and aborts the unpack even though every member extracted fine.
rm -rf stage opt usr deps
mkdir stage
bsdtar -xOf euro-office.deb 'data.tar*' | bsdtar --no-same-owner -xf - -C stage
[ -x stage/opt/euro-office/euro-office/DesktopEditors ] \
    || { echo "DesktopEditors missing in .deb" >&2; exit 1; }
[ -x stage/usr/bin/euro-office-euro-office ] \
    || { echo "vendor launcher missing in .deb" >&2; exit 1; }
[ -f stage/opt/euro-office/euro-office/libcef.so ] \
    || { echo "libcef.so missing in .deb" >&2; exit 1; }

mv stage/opt opt
mkdir -p usr
mv stage/usr/bin usr/bin
rm -rf stage

mkdir -p deps
for deb in libgssapi-krb5-2.deb libkrb5-3.deb libk5crypto3.deb \
           libkrb5support0.deb libkeyutils1.deb; do
    mkdir stage
    bsdtar -xOf "$deb" 'data.tar*' | bsdtar --no-same-owner -xf - -C stage
    # -a, and the -type l test, because the loader looks up the SONAME link
    # (libgssapi_krb5.so.2), not necessarily the regular file behind it.
    find stage/usr/lib -maxdepth 3 \( -type f -o -type l \) -name 'lib*.so*' \
        -exec cp -a {} deps/ \;
    rm -rf stage
done

for so in libgssapi_krb5.so.2 libkrb5.so.3 libk5crypto.so.3 libkrb5support.so.0 \
          libkeyutils.so.1; do
    [ -e "deps/$so" ] || { echo "$so not found in the Debian packages" >&2; exit 1; }
done

# Drop the archives now that the trees are staged — otherwise they sit on the
# user's disk for the life of the install.
rm -f euro-office.deb libgssapi-krb5-2.deb libkrb5-3.deb libk5crypto3.deb \
      libkrb5support0.deb libkeyutils1.deb
