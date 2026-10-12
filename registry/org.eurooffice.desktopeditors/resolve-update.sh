#!/usr/bin/env bash
# Update resolver for Euro-Office Desktop Editors.
#
# Prints the current version + the official amd64 .deb as JSON on stdout:
#   { "version": "9.3.5-2", "releaseDate": "YYYY-MM-DD",
#     "sources": [ { "filename": "euro-office.deb", "url": "..." } ] }
# Logs go to stderr. No hashing, no manifest rewriting — FlatPark downloads the
# URL and computes the extra-data sha256/size at build time. The version is
# compared against the latest <release> in the AppStream metainfo.
#
# The newest GitHub release is not always the one that ships the Linux .deb
# (Windows zips, the help package and the .tar.xz are separate assets), so
# this walks recent releases and takes the newest non-draft, non-prerelease
# whose assets include euro-office-euro-office_<version>_amd64.deb exactly.
# aarch64 is not published: the Kerberos libraries this build needs are
# re-pinned from Debian's amd64 index, which cannot describe an arm64 package.
set -euo pipefail

repo="Euro-Office/DesktopEditors"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need curl; need jq

rels="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$repo/releases?per_page=30")"

# Pick the first release that actually ships the amd64 deb. releases?per_page
# is newest-first, so the first hit is the newest such release.
picked="$(jq -c '
  [ .[] | select(.draft == false and .prerelease == false)
    | . as $r
    | .assets[]
    | select(.name | test("^euro-office-euro-office_[^_]+_amd64\\.deb$"))
    | {name: .name, url: .browser_download_url, published: $r.published_at}
  ] | first // empty
' <<<"$rels")"

[ -n "$picked" ] || { echo "failed to resolve Euro-Office release" >&2; exit 1; }

asset="$(jq -r '.name' <<<"$picked")"
url="$(jq -r '.url' <<<"$picked")"
date="$(jq -r '.published' <<<"$picked" | cut -c1-10)"
version="$(sed -n 's/^euro-office-euro-office_\(.*\)_amd64\.deb$/\1/p' <<<"$asset")"

[ -n "$version" ] && [ -n "$url" ] || { echo "failed to resolve Euro-Office release" >&2; exit 1; }
echo "resolved Euro-Office $version ($date): $url" >&2

jq -n --arg v "$version" --arg d "$date" --arg u "$url" \
  '{version:$v, releaseDate:$d, sources:[{filename:"euro-office.deb", url:$u}]}'
