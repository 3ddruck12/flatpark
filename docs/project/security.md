---
description: How to report a security problem, what happens to a dangerous release, and how the repository is signed.
order: 6
---

# Security

## Reporting a problem

If you find something that puts users at risk (a package that runs or reaches
something it shouldn't, an app release that is malicious, a weakness in how
FlatPark builds, signs or publishes), open an issue at
[github.com/flatpark/flatpark/issues](https://github.com/flatpark/flatpark/issues)
and say in the title that it is a security problem. It is handled before
anything else.

## What is never allowed

Whatever else the rules allow, these are never listed, and are removed at once
if found:

- an app or release that steals data, damages systems, or hides what it does;
- a package that escapes the sandbox without declaring it
  (`--filesystem=host`, the Flatpak control bus), or asks for dangerous
  permissions it can't justify;
- a download that isn't the developer's official file.

## When a release is dangerous

Any maintainer pulls it at once, without waiting for anyone: the app is removed
from the catalog, or rolled back to the last safe version, and published. Within
7 days an issue explains what happened, which versions were affected, and what
users should do.

What pulling can and can't do: it stops new installs and updates. A copy
already installed keeps running until the user removes it, so the write-up says
how (`flatpak uninstall --delete-data <app-id>`).

## How the repository is signed

- The repository is signed with one GPG key. Its long-term master key only
  certifies, and is kept out of CI and backed up offline. The key that signs
  is a subkey, and only the publishing workflow holds it.
- Pull requests, including those from forks, are built without any secret and
  signed with a throwaway key. The publishing key never touches a PR's content.
- Your Flatpak client checks the signature on every install and update, and
  the checksum and size of every downloaded app file.

## What FlatPark checks and what it doesn't

FlatPark checks that every app file is the developer's official release,
pinned by checksum, and that each package does only what it declares. It
doesn't audit the apps' own code, and closed-source apps can't be audited at
all: you trust the developer for what the app does, and FlatPark for how it is
packaged and delivered. [Trust & safety](trust.md) has the details.

## For agents

- **Secrets live only in trusted workflows:** `publish.yml`, `delist-prune.yml`
  and `install-stats.yml`, which run on `main`. `pr-checks.yml` has none.
- **A PR that touches `.github/`, `scripts/` or `config/`, or the resolver of an
  app that already exists,** is flagged by `pr-checks` and needs the owner;
  these run on CI with write access.
- **The release webhook** trusts nothing in a request: it checks the app, its
  registered GitHub source and the release before triggering an update
  ([publish-action](../developers/publish-action.md)).
- **Pulling a release:** delete `registry/<id>/` (or revert the pin to the last
  safe version) in a PR and merge it; publishing removes the app from the
  catalog. Run `delist-prune` by hand (Actions → delist-prune → Run workflow)
  instead of waiting for Saturday to drop its refs from the repository. Then
  open the public write-up.
