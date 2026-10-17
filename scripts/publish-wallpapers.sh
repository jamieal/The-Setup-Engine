#!/bin/bash
#
# Publish a folder of photos as The Setup Engine's wallpaper collection.
#
# Makes a thumbnail for each photo, writes wallpapers.json (title, credit,
# links, SHA-256), and uploads everything to the GitHub release tagged
# "wallpapers" on this repo. The app reads that release; nothing else to do.
#
# Usage:
#   scripts/publish-wallpapers.sh ~/Pictures/Wallpaper\ picks
#   CREDIT="Photo by Jamie Cras" scripts/publish-wallpapers.sh <folder>
#   DRY_RUN=1 scripts/publish-wallpapers.sh <folder>   # build + print, no upload
#
# Photos: JPEG, HEIC or PNG, ideally 5K (5120×2880). The file name becomes the
# title ("golden-hour-dublin.jpg" → "Golden Hour Dublin").
# Needs: gh (signed in), sips and shasum (built into macOS).

set -euo pipefail

SRC="${1:?Usage: $0 <folder of photos>}"
CREDIT="$(echo "${CREDIT:-Photo by Jamie Cras}" | tr -d '"\\')"
TAG="wallpapers"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
BASE="https://github.com/$REPO/releases/download/$TAG"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

entries=()
shopt -s nullglob nocaseglob
for photo in "$SRC"/*.{jpg,jpeg,heic,png}; do
    name="$(basename "${photo%.*}")"
    # Release asset names can't have spaces; make a clean slug.
    slug="$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
    title="$(echo "$name" | tr -d '"\\' | tr '_-' '  ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')"

    sips -s format jpeg -s formatOptions 90 "$photo" --out "$OUT/$slug.jpg" >/dev/null
    sips -Z 640 -s format jpeg -s formatOptions 75 "$photo" --out "$OUT/$slug-thumb.jpg" >/dev/null
    sha="$(shasum -a 256 "$OUT/$slug.jpg" | cut -d' ' -f1)"

    entries+=("$(printf '{"id":"%s","title":"%s","credit":"%s","thumb":"%s/%s-thumb.jpg","full":"%s/%s.jpg","sha256":"%s"}' \
        "$slug" "$title" "$CREDIT" "$BASE" "$slug" "$BASE" "$slug" "$sha")")
    echo "✓ $title"
done

[ ${#entries[@]} -gt 0 ] || { echo "No photos found in $SRC"; exit 1; }

{ printf '{"photos":['; (IFS=,; printf '%s' "${entries[*]}"); printf ']}\n'; } > "$OUT/wallpapers.json"

if [ -n "${DRY_RUN:-}" ]; then
    ls -la "$OUT"
    cat "$OUT/wallpapers.json"
    exit 0
fi

if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" --title "Wallpapers" \
        --notes "Wallpaper collection for The Setup Engine. Managed by scripts/publish-wallpapers.sh."
fi
gh release upload "$TAG" "$OUT"/*.jpg "$OUT/wallpapers.json" --clobber

echo ""
echo "Published ${#entries[@]} wallpapers to $BASE/wallpapers.json"
