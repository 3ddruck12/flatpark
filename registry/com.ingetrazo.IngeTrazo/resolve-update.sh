#!/usr/bin/env bash
# Update resolver for IngeTrazo.
#
# Prints the current version + the Linux x86_64 tarball as JSON on stdout:
#   { "version": "0.5.7", "releaseDate": "YYYY-MM-DD",
#     "sources": [ { "filename": "ingetrazo.tar.gz", "url": "..." } ] }
# Logs go to stderr. No hashing, no manifest rewriting — FlatPark downloads
# the URL and computes the extra-data sha256/size. The version is compared
# against the latest <release> in the AppStream metainfo.
set -euo pipefail

repo="ingelibre/ingetrazo"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need curl; need jq

# releases/latest excludes prereleases and drafts.
rel="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$repo/releases/latest")"

version="$(jq -r '.tag_name | ltrimstr("v")' <<<"$rel")"
date="$(jq -r '.published_at' <<<"$rel" | cut -c1-10)"
# IngeTrazo-<version>-linux-x86_64.tar.gz. The AppImage, the single-file
# .flatpak bundle and the Windows/macOS installers are separate assets.
url="$(jq -r '.assets[] | select(.name | test("linux-x86_64\\.tar\\.gz$")) | .browser_download_url' <<<"$rel" | head -n1)"

[ -n "$version" ] && [ "$version" != "null" ] && [ -n "$url" ] && [ "$url" != "null" ] \
    || { echo "failed to resolve ingetrazo release" >&2; exit 1; }
echo "resolved ingetrazo $version ($date): $url" >&2

jq -n --arg v "$version" --arg d "$date" --arg u "$url" \
  '{version:$v, releaseDate:$d, sources:[{filename:"ingetrazo.tar.gz", url:$u}]}'
