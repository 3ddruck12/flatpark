---
description: Packaging an app from upstream's AppImage, unpacked offline without running it.
order: 3
---

# AppImages

A type-2 AppImage is a small ELF program with a SquashFS image appended to it.
FlatPark never runs it and needs no FUSE: `apply_extra.sh` finds where the
SquashFS starts and unpacks it, leaving the AppImage's own directory tree
(the AppDir) in `/app/extra`. The wrapper then starts the app from that tree.

The runtime has no SquashFS tool, so every AppImage package downloads a second
small file, the `appimage-tools` stack from
[`flatpark/prebuilt`](https://github.com/flatpark/prebuilt). It holds two
programs: `appimage-offset`, which prints where the SquashFS starts, and
`unsquashfs`.

An AppImage brings its own libraries, so it is the format to reach for when
that is what the app needs, above all a Qt app that carries its own Qt (see
[choosing a format](README.md#the-qt-exception)). Otherwise a tarball or `.deb`
of the same release is simpler.

Start from one of these:

- [Mark Shot](../../../registry/io.github.jswysnemc.MarkShot/apply_extra.sh):
  Qt 6 with its own Qt, freedesktop runtime, plus Debian-pinned clipboard tools.
- [Compass](../../../registry/org.tunaos.compass/compass-wrapper): a
  self-contained app started through the AppDir's own `AppRun`.
- [AlterSend](../../../registry/com.altersend.AlterSend/apply_extra.sh): an
  Electron app with the Electron base app and zypak.

## For agents

### The manifest

Pin the tools **outside** the managed block, so the updater, which rewrites that
block from the resolver's output, leaves them alone:

```yaml
sources:
  - type: extra-data
    filename: appimage-tools.tar.xz
    only-arches: [x86_64]
    url: https://github.com/flatpark/prebuilt/releases/download/appimage-tools-v2/appimage-tools-appimage-tools-v2-fd-26.08-x86_64.tar.xz
    sha256: 01ff0b363031060c3d9877bc61b026a1a7422308fd9e5cfda53cc24971b12304
    size: 57220
  # BEGIN MANAGED EXTRA-DATA
  - type: extra-data
    filename: app.AppImage
    # …
  # END MANAGED EXTRA-DATA
```

Copy the current pin from an existing AppImage package; the one above may be
out of date. The tools are extra-data, not a module built into `/app`, because
a system-wide install runs `apply_extra` with only the runtime's `/usr` and
`/app/extra` visible: a tool in `/app/bin` works on a `--user` install and
fails on a system one.

### `apply_extra.sh`

```sh
#!/bin/sh
set -eu

extra_root="${EXTRA_ROOT:-/app/extra}"
cd "$extra_root"

for f in app.AppImage appimage-tools.tar.xz; do
    [ -f "$f" ] || { echo "missing extra-data: $f" >&2; exit 1; }
done
rm -rf app squashfs-root appimage-tools

bsdtar --no-same-owner -xf appimage-tools.tar.xz
tools=appimage-tools/bin

# Find where the appended SquashFS starts, then unpack from there.
offset="$("$tools/appimage-offset" app.AppImage)"
case "$offset" in
    ''|*[!0-9]*) echo "appimage-offset did not return a number: '$offset'" >&2; exit 1 ;;
esac
"$tools/unsquashfs" -q -no-xattrs -d squashfs-root -o "$offset" app.AppImage >/dev/null

[ -x squashfs-root/usr/bin/example ] || { echo "no usr/bin/example in the AppImage" >&2; exit 1; }
mv squashfs-root app
rm -rf appimage-tools app.AppImage appimage-tools.tar.xz
```

- `-no-xattrs`: the sandbox can't set them, and the app doesn't need them.
- **Keep the AppDir's tree whole** unless you know the app finds its files
  another way. Bundled binaries usually locate their libraries through an
  `$ORIGIN/../lib` RUNPATH and their plugins through a `qt.conf` next to them,
  which only work while `usr/bin`, `usr/lib` and `usr/plugins` stay siblings.
- **Missing pieces go next to the tree, not into it.** Mark Shot's app looks for
  plugins at a path the bundle doesn't use, so `apply_extra.sh` adds a symlink
  beside the vendor's files rather than moving them.

### Starting the app

Look at `AppRun` and the AppDir's `.desktop` file first; they show how upstream
starts it.

- **`AppRun` is a symlink to the binary:** run the binary directly
  ([OpenCadStudio](../../../registry/io.github.HakanSeven12.OpenCadStudio/apply_extra.sh)
  resolves the name through the link, so a renamed binary still works).
- **`AppRun` is a script that only sets variables and starts the app:**
  `exec` it ([Compass](../../../registry/org.tunaos.compass/compass-wrapper)),
  or set the same variables in the wrapper and run the binary
  ([Mark Shot](../../../registry/io.github.jswysnemc.MarkShot/mark-shot-wrapper)).
- **A linuxdeploy AppDir with `apprun-hooks/`:** the GTK hook points GTK,
  GdkPixbuf, GSettings and GObject introspection at the bundled GTK, and forces
  `GDK_BACKEND=x11`. If the app runs on the runtime's GTK, put it on the GNOME
  runtime, skip `AppRun`, and set only the app's own variables
  ([Tavern](../../../registry/org.tunaos.tavern/tavern-wrapper), a Python and
  GTK 4 app). If it needs its bundled GTK, `exec AppRun` and grant
  `--socket=x11`; the bare binary runs with half its GTK missing.
- **Electron:** as for [tarballs](tar.md#electron-tarballs-and-zips): Electron
  base app, `zypak-wrapper`, `unset ELECTRON_RUN_AS_NODE`. Read the launcher
  name from the AppDir rather than hardcoding it
  ([AlterSend](../../../registry/com.altersend.AlterSend/apply_extra.sh)).

`AppRun` is the format's fixed entry point, so naming it is safe.

Don't put the bundle's `usr/lib` on `LD_LIBRARY_PATH` unless upstream's own
launcher does. AppImages often carry their own copies of libraries the runtime
also has, and a global path makes every child process load them too.

### Sandbox notes

- **Qt platform plugins.** A bundled Qt often has only `xcb`, or the Wayland
  plugin without `libQt5WaylandClient`. Then: `--socket=x11`,
  `--unset-env=QT_QPA_PLATFORM`, and `QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"`
  in the wrapper. More in [choosing a format](README.md#things-to-check-in-a-self-contained-appimage).
- **A bundled Qt may have no portal platform theme,** so file dialogs
  are Qt's own and only see what the sandbox grants. Grant the directories the
  app saves to by default (`xdg-pictures`, `xdg-documents`), not `home`.
- **`--persist=.dir` is ignored when `home` is granted too:** the broader mount
  hides it. For an app that writes a `~/.dotdir`, pick one: `--persist=.dir`
  with only `xdg-*` grants, or `--filesystem=~/.dir:create`.
- **Testing a rebuild:** `flatpak install --reinstall` from a local `file://`
  remote can keep the old commit. Uninstall, then install.
