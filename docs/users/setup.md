---
description: Add the FlatPark remote once, then install any app, for yourself or for everyone on the computer.
order: 1
---

# Setting up FlatPark

FlatPark is a signed Flatpak remote. Add it once, add Flathub for the runtimes
the apps run on, and every app in the catalog can be installed with one command
or the Install button on its page.

You need Flatpak itself; most distributions ship it or have it one package away
([flatpak.org/setup](https://flatpak.org/setup/)).

## For yourself (recommended)

Installs into your home directory and needs no admin rights.

```sh
flatpak --user remote-add --if-not-exists flatpark https://dl.flatpark.org/flatpark.flatpakrepo
flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak --user install flatpark <app-id>
```

## For everyone on the computer

The same commands without `--user`; Flatpak asks for an admin password.

```sh
flatpak remote-add --if-not-exists flatpark https://dl.flatpark.org/flatpark.flatpakrepo
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flatpark <app-id>
```

Stay with one choice: an app installed system-wide needs the remotes added
system-wide too. If Flathub is already set up, the second command does nothing.

## Installing from an app's page

Every app page shows its id and an **Install** button that copies the install
command. Its menu also offers a `.flatpakref` file, which opens in your software
centre (GNOME Software, KDE Discover).

The remote is signed with one key, and your client checks every download
against it. [Trust & safety](../project/trust.md) explains what that covers.
