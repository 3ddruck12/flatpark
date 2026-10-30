#!/usr/bin/env bash
# Update resolver for ConstructCAD.
#
# The same GitHub release also ships installers, an AppImage, macOS and
# Windows archives. Take only
# constructcad-v<version>-x86_64-unknown-linux-gnu.tar.gz.
# Prints JSON on stdout:
#   { "version": "0.7.0", "releaseDate": "YYYY-MM-DD",
#     "sources": [ { "filename": "constructcad.tar.gz", "arch": "x86_64", "url": "..." } ] }
# Logs go to stderr. No hashing, no manifest rewriting.
set -euo pipefail

repo="francisreboucas/constructcad"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need curl; need jq

best_published=""
best_version=""
best_date=""
best_url=""

page=1
while [ "$page" -le 4 ]; do
  rels="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    "https://api.github.com/repos/$repo/releases?per_page=20&page=$page")"
  count="$(jq 'length' <<<"$rels")"
  [ "$count" -gt 0 ] || break

  while IFS="$(printf '\t')" read -r published version date url; do
    [ -n "$published" ] || continue
    if [ -z "$best_published" ] || [ "$published" \> "$best_published" ]; then
      best_published="$published"
      best_version="$version"
      best_date="$date"
      best_url="$url"
    fi
  done < <(jq -r '
    .[] | select(.draft | not) | select(.prerelease | not) | . as $r
    | .assets[]
    | select(.name | test("^constructcad-v[0-9.]+-x86_64-unknown-linux-gnu\\.tar\\.gz$"))
    | [$r.published_at,
       (.name | capture("^constructcad-v(?<v>[0-9.]+)-x86_64-unknown-linux-gnu\\.tar\\.gz$").v),
       ($r.published_at[0:10]),
       .browser_download_url]
    | @tsv
  ' <<<"$rels")

  page=$((page + 1))
done

[ -n "$best_version" ] && [ -n "$best_url" ] || { echo "failed to resolve ConstructCAD release" >&2; exit 1; }
echo "resolved ConstructCAD $best_version ($best_date): $best_url" >&2

jq -n --arg v "$best_version" --arg d "$best_date" --arg u "$best_url" \
  '{version:$v, releaseDate:$d, sources:[
     {filename:"constructcad.tar.gz", arch:"x86_64", url:$u}
   ]}'
