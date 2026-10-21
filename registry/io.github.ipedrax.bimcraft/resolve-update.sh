#!/usr/bin/env bash
# Update resolver for BIMCraft.
#
# Prints the current version + the official x86_64 tarball as JSON on stdout:
#   { "version": "0.6.0", "releaseDate": "YYYY-MM-DD",
#     "sources": [ { "filename": "bimcraft.tar.gz", "arch": "x86_64", "url": "..." } ] }
# Logs go to stderr. No hashing, no manifest rewriting — FlatPark downloads the
# URL and computes the extra-data sha256/size at build time. The version is
# compared against the latest <release> in the AppStream metainfo.
#
# bimcraft-<ver>-linux-x86_64.tar.gz exactly: excludes the aarch64 and riscv64
# tarballs, and the .flatpak/.deb/.rpm/.AppImage of the same build. aarch64 is
# not published.
set -euo pipefail

repo="IPedrax/BIMCraft"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need curl; need jq

rel="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$repo/releases/latest")"

version="$(jq -r '.tag_name | ltrimstr("v")' <<<"$rel")"
date="$(jq -r '.published_at' <<<"$rel" | cut -c1-10)"
url="$(jq -r --arg n "bimcraft-$version-linux-x86_64.tar.gz" \
  '.assets[] | select(.name == $n) | .browser_download_url' <<<"$rel" | head -n1)"

[ -n "$version" ] && [ -n "$url" ] || { echo "failed to resolve BIMCraft release" >&2; exit 1; }
echo "resolved BIMCraft $version ($date): $url" >&2

jq -n --arg v "$version" --arg d "$date" --arg u "$url" \
  '{version:$v, releaseDate:$d, sources:[
     {filename:"bimcraft.tar.gz", arch:"x86_64", url:$u}
   ]}'
