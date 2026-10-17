---
description: Adding an app step by step — build it, test it locally, open the PR.
order: 4
---

# Publishing guide

This page walks through adding an app: build it, test it, open the PR. Read
[what a package is](basics.md) first for the files and how they run, and
[choosing a format](formats/README.md) for which download to package.

Any app with a public download is welcome; FlatPark does not host builds.
**Electron and Tauri apps are welcome**, and so are **closed-source apps**: the
license is not the bar; where the bytes come from is. Packages worth reading
before you write your own:

- **Electron** —
  [`is.folo.Folo`](https://github.com/flatpark/flatpark/tree/main/registry/is.folo.Folo)
  and [`org.electerm.Electerm`](https://github.com/flatpark/flatpark/tree/main/registry/org.electerm.Electerm):
  the Electron base app plus `zypak-wrapper`, so Chromium keeps its internal
  sandbox.
- **Tauri / WebKitGTK** —
  [`com.aeroftp.AeroFTP`](https://github.com/flatpark/flatpark/tree/main/registry/com.aeroftp.AeroFTP):
  a Tauri app with a tray icon. Its wrapper exports
  `WEBKIT_DISABLE_DMABUF_RENDERER=1` (without it WebKitGTK paints a blank
  window under many drivers). If the app uses Tauri's `tray-icon`, it also
  needs the Ayatana appindicator stack: the GNOME runtime does not ship it,
  and `tray-icon` `dlopen`s it and can panic when it is absent. **Do not copy
  and maintain the five-module source recipe in each app.** Use FlatPark's
  `ayatana-stack` from [prebuilt](prebuilt.md#the-stacks) as an archive
  module, copied from AeroFTP's manifest.
- **Host-dependent behavior, payload untouched** —
  [`io.enpass.Enpass`](https://github.com/flatpark/flatpark/tree/main/registry/io.enpass.Enpass):
  Enpass validates the browser behind its extension's localhost connection by
  running `lsof` and reading `/proc`, which can't work from inside the sandbox.
  Rather than patch the vendor binary, the package puts small `lsof`/`readlink`/
  `cat` shims on `PATH` that forward to the host via `flatpak-spawn --host`.
  Nothing is injected into the app's process, and the shipped Enpass binary is
  still the vendor's own, byte for byte. (Injected code, such as an `LD_PRELOAD`
  shim, is only accepted in a closed-source app whose description says what it
  is and why; an open-source app that needs it is not listed — the fix belongs
  upstream.) Note what this costs: it needs
  `--talk-name=org.freedesktop.Flatpak`, normally an auto-reject, so the package
  declares it under `policy.dangerous_permissions` and argues for it — expect
  that level of scrutiny if you go this route.

## Libraries the runtime lacks

Shared support libraries (the Ayatana tray stack for Tauri apps, mpv, ffmpeg,
database clients, the AppImage tools) come from
[`flatpark/prebuilt`](https://github.com/flatpark/prebuilt). See
[prebuilt stacks](prebuilt.md) for the list, how to pin one, and when to add a
new one. Never compile a dependency inside an app's manifest.

## Add an app

Create one directory under `registry/` named exactly for the app id, with the
files described in [what a package is](basics.md#the-files): the descriptor,
the manifest, `apply_extra.sh`, a wrapper, the desktop entry, metainfo, icon,
and a `resolve-update.sh`.

Then validate and build locally. If your machine has no `flatpak-builder`
package the tooling uses the Flathub build of it, which is the recommended way
— it bundles the freedesktop SDK (`bsdunzip`, `appstreamcli`, `node`, …), so
a manifest builds against that fixed toolchain instead of whatever your distro
ships. Install it once:

```sh
flatpak install flathub org.flatpak.Builder
node scripts/read-descriptor.mjs registry/com.example.App/flatpark.yml
./scripts/publish.sh --verify com.example.App
```

A host `flatpak-builder` binary, if you have one, is used in preference (that
is what CI does, because the sandboxed builder needs a session bus to reach
the host's flatpak and a headless runner has none).

The sandboxed builder has its own `/tmp`, so a `REPO_DIR`/`OUT_DIR`/
`GNUPGHOME_DIR` you point somewhere yourself has to live under `$HOME` or the
repo; the scripts stop with an explanation if it doesn't.

### Test without polluting your everyday Flatpak

`publish.sh --verify` adds a **temporary** local `file://` remote named
`flatpark-local` to your **`--user`** installation, installs the app from it to
prove the built repo is installable, then uninstalls the app and deletes the
remote again — your real `flatpark` remote is never touched (the script refuses
to run if the two names collide). If an app under verify was already installed
from another remote, verify moves it aside with `--reinstall` and restores it
from its original remote during cleanup.

To keep the app installed after verify for manual runtime testing, set
`FLATPARK_VERIFY_KEEP=1`:

```sh
FLATPARK_VERIFY_KEEP=1 ./scripts/publish.sh --verify com.example.App
flatpak --user run com.example.App
# ... exercise the core feature, then clean up:
flatpak --user uninstall -y com.example.App
flatpak --user remote-delete --force flatpark-local
rm -rf ~/.var/app/com.example.App
```

The scratch repo (`out/repo`) is rebuilt on every run, so its commits drift from
whatever you have installed — with `FLATPARK_VERIFY_KEEP=1`, don't leave the
`flatpark-local` remote around between sessions. For longer-lived manual
testing, keep builds in a separate, throwaway installation so they never touch
your normal Flatpak state:

```sh
# one-time: create an isolated installation named "test"
sudo install -d /etc/flatpak/installations.d
printf '[Installation "test"]\nPath=%s/.local/share/flatpak-test\nDisplayName=FlatPark test\n' \
  "$HOME" | sudo tee /etc/flatpak/installations.d/test.conf >/dev/null

# install the freshly built app into it, then wipe it when done
flatpak --installation=test remote-add --no-gpg-verify flatpark "file://$PWD/out/repo"
flatpak --installation=test install flatpark com.example.App
flatpak --installation=test uninstall --all
```

No root, or you would rather not touch `/etc`? Install into your normal `--user`
installation under a **remote name of its own**. The conflict the paragraph above
warns about comes from sharing the `flatpark` remote name with the real one, not
from the installation itself:

```sh
flatpak --user remote-add --if-not-exists --no-gpg-verify test-tmp "file://$PWD/out/repo"
flatpak --user install -y test-tmp com.example.App
# ... launch it, exercise the core feature ...
flatpak kill com.example.App
flatpak --user uninstall -y com.example.App
flatpak --user remote-delete test-tmp
rm -rf ~/.var/app/com.example.App
```

> **Do not reach for `FLATPAK_USER_DIR` to get isolation.** It does produce a
> throwaway installation, but that installation is not registered in
> `/etc/flatpak/installations.d`, so the **host's Flatpak portal does not know it
> exists**. Anything that relies on `flatpak-spawn` then fails with
> `app/<id>/x86_64/stable ... not installed` — and that includes **glycin**, the
> image decoder behind gdk-pixbuf in the GNOME 48+ runtimes, which decodes in a
> sub-sandbox it spawns for itself. The app aborts on startup:
>
> ```
> Gtk:ERROR:../gtk/gtkiconhelper.c:495:ensure_surface_for_gicon: assertion failed
> (error == NULL): Failed to load .../image-missing.png:
> Loader process exited early with status '1'
> ```
>
> This looks exactly like the packaged app crashing. It is not — the same build
> starts fine from a registered installation. Use `--installation=test`, or the
> temporary-remote recipe above.

Open a PR. `pr-checks` validates the descriptor, runs the test suite, checks for
dead links, and builds the changed app — including from a fork, once a maintainer
approves the workflow run (fork builds get no secrets and are signed with a
throwaway key). On merge, `publish` builds and publishes it.

## Sandbox & permissions

Ship the tightest `finish-args` that still let the app's core feature work.
FlatPark surfaces permissions on each app's detail page, and broad grants will be
questioned in review.

**Optional capabilities are not granted by default.** If the app can do more with
a broader permission — reading host SSH keys, serial devices, the whole home
directory — leave it out of `finish-args` and instead document the `flatpak
override` command that turns it on, so each user decides for themselves. Put that
documentation in the app's `metainfo.xml` description (it renders on the app's
page), and explain in the PR body why the capability exists at all. See
[`org.electerm.Electerm`](https://github.com/flatpark/flatpark/tree/main/registry/org.electerm.Electerm)
for the pattern:

```xml
<p>A few optional capabilities are not granted by default; enable the ones you
   need with "flatpak override":</p>
<ul>
  <li>Reuse your existing host SSH keys: <code>flatpak override --user --filesystem=~/.ssh:ro org.electerm.Electerm</code></li>
  <li>Serial-port connections: <code>flatpak override --user --device=all org.electerm.Electerm</code></li>
</ul>
```

If a permission is genuinely required for the app to function at all, keep it in
`finish-args`, list it under `policy.dangerous_permissions` if it is high-risk,
and justify it in the PR. Sandbox-escape permissions (`--filesystem=host`,
`--filesystem=/`, `--talk-name=org.freedesktop.Flatpak`) are rejected by default;
the only way past that is to declare the permission under
`policy.dangerous_permissions` and make the case for it, which earns a human
review rather than an automatic pass (Enpass is the one package that has).

## What we review (and what gets a PR rejected)

Every PR is checked against the full
[review runbook](../reviewers/review-runbook.md).
To pre-empt the common rejections, make sure your submission:

- **Has actually been installed and run** — before opening the PR, build it,
  `flatpak install` it into the isolated test installation above, launch the app,
  and confirm the core feature works. A manifest that only passes `--verify` is
  not tested. Record in the PR body what you exercised and what you couldn't
  (GUI rendering on a real session, login flows, hardware paths).
- **Grants no optional permission by default** — broad capabilities are
  documented as opt-in `flatpak override` commands in the metainfo, not baked
  into `finish-args`; anything that stays in `finish-args` is justified in the PR.
- **Pins every remote source** — `extra-data`/`archive` need `sha256` (and
  `extra-data` a non-zero `size`); `git` needs an immutable `commit`. (`type:
  file` packaging files need no pin.)
- **Downloads only from the official channel** — the vendor's own domain or the
  genuine upstream repo, never a personal account or a mirror.
- **Repackages the official build unmodified** — `build-commands` only install
  the wrapper/desktop/metainfo/icon and an `apply_extra` that unpacks the
  download; don't patch, recompile, or change the app's behavior. Adapting the
  app to the sandbox *from the outside* is fine — wrapper env vars, missing
  libraries built as extra modules, `PATH` shims (see cc-switch and Enpass
  above) — as long as the vendor's own bytes are what actually run. Injecting
  code into the app's process (an `LD_PRELOAD` shim, a patched or replaced file)
  is not accepted for open-source apps; a closed-source app may carry it only if
  its metainfo description says what is injected and why.
- **Declares its packaging level** — anything beyond a plain launch (preset
  settings, injected code, changed files, host commands, a disabled inner
  sandbox) is listed under `packaging:` in `flatpark.yml` with a one-sentence
  English and Chinese description. It shows on the app page; see
  [Trust & safety](../project/trust.md#packaging) for the levels.
- **Uses a plain resolver** — `update.command` is a simple relative script path
  like `./resolve-update.sh` (it runs in CI).
- **Declares its `policy`** — set `proprietary` honestly and list any high-risk
  permissions in `dangerous_permissions`.
- **Doesn't fetch-and-run arbitrary code** — a vendor's own self-updater writing
  into the app's data directory is fine; downloading and executing unpinned
  third-party code is not.
- **Avoids sandbox-escape permissions** — no `--filesystem=host`,
  `--filesystem=/`, or `--talk-name=org.freedesktop.Flatpak`, unless declared in
  `policy.dangerous_permissions` and argued for.
- **Ships an accepted artifact** — tarball, `.deb`, `.rpm`, zip, an official
  installer, or an AppImage (unpacked offline, never executed).
- **Has a legitimate purpose** — non-FOSS is fine; piracy, malware, and trademark
  impersonation are not.

Non-FOSS commercial apps (e.g. brokers) are welcome on the same bar: official
source, unmodified, pinned.
