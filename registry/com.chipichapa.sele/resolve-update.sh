#!/usr/bin/env bash
set -euo pipefail

repo="Chipi-Chapa-Corp/sele"
headers=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    headers=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi
release="$(curl -fsSL --retry 3 "${headers[@]}" "https://api.github.com/repos/$repo/releases/latest")"

# Require one official Linux x64 tarball; never fall back to the Flatpak bundle,
# a different platform, a prerelease, or an expiring Actions artifact URL.
jq -e '
    (.tag_name | ltrimstr("v")) as $version |
    [.assets[] | select(.name == "sele-linux-x64.tar.gz") | .browser_download_url] as $urls |
    if ($version | length) > 0 and ($urls | length) == 1 then
        {version: $version, releaseDate: (.published_at | split("T")[0]),
         sources: [{filename: "sele.tar.gz", arch: "x86_64", url: $urls[0]}]}
    else error("latest stable Sele release must contain exactly one sele-linux-x64.tar.gz asset") end
' <<<"$release"
