---
description: The few rules every other FlatPark rule follows from.
order: 2
---

# Principles

Every rule in these docs comes from one of these. When a case isn't covered,
decide it by them, and by the [goal](about.md#goal): an efficient remote that
is easy to take part in, where speed matters most.

1. **The developer's own build, nothing else.** Apps come from the developer's
   official download, fetched on your machine at install time (extra-data).
   FlatPark never rebuilds an app and never hosts its bytes. An app that has to
   be built from source is built in its own public `-release` repository, and
   that release is used like any other download.
2. **Open-source apps run unmodified.** Nothing is injected into their
   process and none of their files is changed. If one can't work in the sandbox
   without that, the fix belongs upstream and the app isn't listed until then.
3. **Closed-source changes are disclosed.** A closed-source app may need a
   change to work in the sandbox; when it does, its page says exactly what and
   why.
4. **Every package says what it does.** Each one declares its packaging level
   (Unmodified, Adapted, Modified, Reduced isolation), and CI checks the
   declaration against what the package actually does.
5. **Least privilege by default.** A package grants what the app's main job
   needs; anything more is the user's choice, documented as a command.
6. **The developer has the final word on their app**: whether it's listed, how
   it's packaged, what is said about it. No say over other apps.
7. **Judge the package, not how it was written.** An app is listed or not on
   what it does and how it's packaged, not on whether it was written with AI.
8. **One runtime version for the whole catalog.** Every app moves to the new
   version together, so users keep one copy on disk.
9. **Test before shipping, fix fast after.** Our own changes are tested
   before they ship ([testing playbook](../reviewers/testing-playbook.md));
   upstream releases ship at once and are fixed quickly when they break.
10. **Decisions in public.** Rules, packages, reviews, incidents and removals
    are all in the open repository.
