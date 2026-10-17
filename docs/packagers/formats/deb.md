---
description: Packaging an app from upstream's .deb (or .rpm), and pinning Debian packages for missing tools.
order: 2
---

# Debian packages

A `.deb` is an `ar` archive with the app's files in a `data.tar` member, laid
out the way they would be installed: `usr/bin`, `usr/lib/<name>`, `opt/<Name>`,
`usr/share`. The runtime has no `ar` or `dpkg`, but `bsdtar` reads the container,
so `apply_extra.sh` pipes the data member into a second `bsdtar` and keeps the
part of the tree the app runs from.

Nothing in the package's maintainer scripts (`postinst` and friends) runs, and
its `Depends` are not installed. Read both before packaging: whatever they would
have done or pulled in has to come from the runtime, the wrapper, or a second
download.

Start from one of these:

- [Tabularis](../../../registry/dev.tabularis.Tabularis/apply_extra.sh): a
  single Tauri binary on the GNOME runtime.
- [Folo](../../../registry/is.folo.Folo/apply_extra.sh): an Electron app under
  `usr/lib/folo`, with the Electron base app. It reads the app directory and
  launcher name from the `.deb`'s own `usr/bin` symlink rather than hardcoding
  them.
- [Audionaut](../../../registry/app.audionaut.Audionaut/apply_extra.sh): on the
  freedesktop runtime.

## For agents

### `apply_extra.sh`

```sh
#!/bin/sh
set -eu

# Runs offline at install time inside org.freedesktop.Platform. The .deb keeps
# the Electron app under usr/lib/example; keep that directory at a stable path.

extra_root="${EXTRA_ROOT:-/app/extra}"
cd "$extra_root"

[ -f app.deb ] || { echo "missing extra-data: app.deb" >&2; exit 1; }

rm -rf stage app
mkdir stage
# The runtime has no ar/dpkg; bsdtar reads the .deb's ar container directly.
# --no-same-owner: a system-wide install runs this as root with no capabilities.
bsdtar -xOf app.deb 'data.tar*' | bsdtar --no-same-owner -xf - -C stage
[ -x stage/usr/lib/example/example ] || { echo "example not found in .deb" >&2; exit 1; }
mv stage/usr/lib/example app
rm -rf stage app.deb
```

To see what is in a `.deb` before writing this:

```sh
bsdtar -xOf app.deb 'data.tar*' | bsdtar -tvf -           # the files
bsdtar -xOf app.deb 'control.tar*' | bsdtar -xOf - ./control    # Depends
bsdtar -xOf app.deb 'control.tar*' | bsdtar -xOf - ./postinst   # what install would run
```

### What to keep

- **Electron:** the directory under `usr/lib/<name>` or `opt/<Name>` that holds
  the binary and `resources/`. The rest of the [tarball notes on
  Electron](tar.md#electron-tarballs-and-zips) apply: Electron base app, zypak,
  `unset ELECTRON_RUN_AS_NODE`. Debian packages often record `chrome-sandbox`
  setuid; clear it with `chmod -R a-s app` so a system install doesn't write a
  setuid file.
- **Tauri:** if the package has only `usr/bin/<name>`, moving that one binary is
  enough (Tabularis). **If it also has `usr/lib/<Name>/`, keep the `usr` tree
  whole** (`mv stage/usr app/usr`) and run `app/usr/bin/<name>`. Tauri looks for
  its resources at `<exe dir>/../lib/<Name>`; a flattened binary looks in the
  runtime's `/usr/lib` instead, finds nothing, and usually runs on silently
  without them. Never set `APPDIR` to point it elsewhere: Tauri panics when
  `APPDIR` is set outside an AppImage.
- **Desktop entry, icons, metainfo** under `usr/share` are not used from here.
  Copy the icon into the package directory once, and write our own desktop
  entry and metainfo.

### `Depends`

Every library in `Depends` (and every `NEEDED` entry of the binary) must exist
in the runtime you chose, or be shipped. Check with `readelf -d`, then look for
each soname in the runtime:

```sh
ls "$(flatpak info --show-location org.gnome.Platform//51)"/files/lib/x86_64-linux-gnu/ | grep libsecret
```

A Qt `.deb` linked against the system Qt is the case that usually fails; see
[choosing a format](README.md#the-qt-exception).

### Pinning a Debian package for a missing tool

When the app shells out to a command neither the runtime nor its own package
ships (a clipboard helper, Ghostscript, `sshpass`), look in this order:
upstream's own Linux binary, then a Debian package pinned as extra-data, then
a [prebuilt stack](../prebuilt.md).

A Debian pin goes in its own managed block, which `debian-pins.yml` re-resolves
from the suite's package index:

```yaml
# BEGIN MANAGED DEBIAN trixie main
- type: extra-data
  filename: xclip.deb          # filename minus .deb is the package name
  only-arches: [x86_64]
  url: https://deb.debian.org/debian/pool/main/x/xclip/xclip_0.13-4_amd64.deb
  sha256: 14203d9a…
  size: 21328
# END MANAGED DEBIAN
```

[Mark Shot](../../../registry/io.github.jswysnemc.MarkShot/apply_extra.sh) pins
`wl-clipboard`, `xclip` and `libxmu6` this way. Lessons from doing it:

- **A stable suite (`trixie`) moves far less than `sid`.** Debian deletes a
  superseded package from the pool at once, and from then until the re-pin job
  runs every new install fails on the download, while existing installs carry
  on. Use `sid` only when stable's version is too old.
- **Copy shared libraries with their soname links:** `find … \( -type f -o
  -type l \) -name 'libXmu.so.*'`. A plain `-type f` drops `libXmu.so.6 ->
  libXmu.so.6.2.0`, and the soname link is what the loader looks for.
- **Data lives in other packages.** Debian splits data into `Architecture: all`
  packages that neither `Depends` on the library nor soname analysis reveal
  (Ghostscript's ICC profiles in `libgs-common`, its fonts in
  `fonts-urw-base35`). Only running the tool finds them.
- **Give each tool its own wrapper** that sets its library path; don't add the
  pinned libraries to the app's `LD_LIBRARY_PATH`, where a second fontconfig or
  freetype would shadow the runtime's for the whole app.
- **"Detected" is not "works."** Apps often only test that a command exists.
  Run the feature that uses it, inside the sandbox.

### rpm

Treat an `.rpm` like a `.deb`: `bsdtar --no-same-owner -xf app.rpm -C stage`
unpacks its payload directly. Use it only when upstream publishes nothing else;
the layout and the `Requires` need the same checks as above.
