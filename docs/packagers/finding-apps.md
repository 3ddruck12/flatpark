---
description: Where FlatPark finds apps worth packaging, how to check one is wanted and not already served, and how to choose between them.
order: 0
---

# Finding apps

Most apps on FlatPark were found, not submitted. The aim is good desktop apps
that publish an official Linux build and that Flatpak users can't get yet, or
can only get in a broken or outdated form. These are the places to look, and
how to choose.

## Where to look

- **Popular apps on GitHub.** Desktop apps built with Electron, Tauri, Flutter,
  Qt, GTK and the like that publish Linux release files but no Flatpak
  repository. This is the widest channel.
- **Flathub submissions turned down for how they were made.** Many new apps
  submitted to Flathub are closed with an "AI Slop" label or a policy reason
  (an AI-written manifest, a requirement to build from source). Some are real,
  working apps, and they fit FlatPark well.
- **Other closed Flathub submissions.** Vendor apps submitted by third parties
  as extra-data and closed because the vendor hadn't consented, and apps whose
  submission went stale.
- **Flathub packages that fell behind.** Packages maintained by someone other
  than the developer that stopped following upstream releases.
- **Requests.** Issues on FlatPark, and Flatpak requests on the app's own
  tracker.

## Choosing

Rank candidates by fit, not popularity. A couple of hundred GitHub stars is
already enough; past that, stars say nothing. A young project with few stars
can be a good pick if it is actively released and used. What matters:

- an official Linux build, released recently, at a stable URL;
- not on Flathub from its developer ([can it be packaged?](can-it-be-packaged.md));
- its main feature works in the sandbox;
- people want it: requests on its tracker, a Flathub attempt that stalled;
- a reasonable download size.

The best openings are developers who already want a Flatpak but haven't got
there: they build a `.flatpak` bundle but have no repository users can update
from, or they've said in an issue they'd like one and lack the time.

## For agents

### GitHub popular apps

Search repositories by toolkit topic, recently pushed, then keep those whose
latest release has a Linux file:

```sh
for t in tauri electron flutter-desktop wails gpui iced egui slint avalonia compose-desktop qt6 gtk4; do
  gh api -X GET search/repositories -f q="topic:$t stars:>200 pushed:>=<date>" \
    -f per_page=100 --paginate -q '.items[].full_name'
done | sort -u > candidates.txt
```

For each repository: `gh api repos/<repo>/releases/latest` and look for an
x86_64 `.deb`, `.tar.gz`, `.zip` or AppImage published in the last few months.
Drop apps already in `registry/`.

### Flathub checks

- Fetch the full id list once, `curl -s https://flathub.org/api/v2/appstream`,
  and match against it, by id and by name. Flathub's search endpoint misses
  many apps that are there; don't rely on it.
- For an app that is there, look at who commits to `github.com/flathub/<id>`.
  The developer or a project member means it is theirs: skip it. A third party,
  or Flathub's own maintainers keeping it alive, means it may qualify with a
  reason.
- Whether upstream's repository has a Flatpak manifest says nothing about who
  owns the Flathub entry.

### Flathub's closed submissions

```sh
# turned down with the AI Slop label
gh api -X GET search/issues -f q='repo:flathub/flathub is:pr label:"AI Slop" created:>=<date>'

# closed without merging, other reasons
gh search prs --repo flathub/flathub --state closed --merged=false --base new-pr \
  --closed '<from>..<to>' --limit 1000 --json number,title,labels,url
```

For the second list, read the reviewers' comments for the reason, and look at
the diffs: a `type: extra-data` source marks a vendor binary someone tried to
submit. Flathub requires the vendor's consent for those; FlatPark doesn't, but
the vendor still decides whether it stays.

### Per candidate

- **Demand:** `gh api -X GET search/issues -f q='repo:<owner>/<repo> flatpak in:title,body'`.
  Read the maintainer's replies; their concerns often name the real blocker.
- **Prior attempts:** `gh api -X GET search/issues -f q='repo:flathub/flathub is:pr <name> in:title'`,
  and why each closed.
- **The developer's own plans:** an open Flathub PR by the maintainer, or a
  statement that they're working on an official Flatpak, means skip it.
- **Commonly out:** VPN and proxy clients that need a TUN device, apps whose main
  job is to change the host (hosts files, system settings), apps that drive a
  host toolchain or daemon (Docker, KVM, a host CLI), and apps with no licence
  that aren't vendor binaries.

Record what you found; the PR and any message to the developer use it. Then
package it with the [playbook](playbook.md).
