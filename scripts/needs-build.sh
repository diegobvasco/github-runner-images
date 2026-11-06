#!/usr/bin/env bash
# Detect which images need to be built between two commits.
#
# A change under images/base/ invalidates the base image and, with it, every
# image that builds on top of it. A change anywhere else under images/ maps to
# the nearest ancestor directory containing a Dockerfile (any depth), so both
# one-level (images/foo) and nested (images/php/8.4) images are supported.
#
# Prints GitHub Actions outputs on stdout (logs go to stderr):
#   has_base=true|false
#   images={"path":["images/php/8.4",...]}
#
# Usage: needs-build.sh [--base <sha>] [--head <sha>] [--all]
#   --base <sha>  Base commit to diff against (default: HEAD~1)
#   --head <sha>  Head commit to diff (default: HEAD)
#   --all         Treat every image as changed (mirrors a manual dispatch)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_tools git python3

usage() {
  sed -n '2,/^set -e/{s/^# \?//; /^set -e/d; p}' "$0" >&2
}

base=""
head=""
all=false
base_set=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) [[ $# -ge 2 ]] || die "--base requires a commit"; base="$2"; base_set=true; shift 2 ;;
    --head) [[ $# -ge 2 ]] || die "--head requires a commit"; head="$2"; shift 2 ;;
    --all) all=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

cd "$(git_root)"

has_base=false
declare -A changed=()

if [[ "$all" == true ]]; then
  has_base=true
else
  [[ -n "$head" ]] || head="$(git rev-parse HEAD)"
  if [[ "$base_set" == false ]]; then
    base="$(git rev-parse "$head~1" 2>/dev/null || true)"
  fi
  base="$(normalize_base "$base" "$head")"

  # A base commit missing from this clone would silently produce an empty
  # diff (e.g. after a force-push); fall back to a full build instead.
  if ! git cat-file -e "$base" 2>/dev/null; then
    warn "base commit '$base' not found locally; assuming a full build"
    base="$EMPTY_TREE_SHA"
  fi

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    case "$file" in
      images/base/*)
        # Any change under images/base invalidates the base image, and with
        # it every image that builds on top of it.
        has_base=true
        ;;
      images/*)
        # Map the changed file to its image: the nearest ancestor directory
        # that contains a Dockerfile.
        if dir="$(image_dir_for_path "$file")"; then
          changed["$dir"]=1
        fi
        ;;
    esac
  done < <(git diff --name-only "$base" "$head")
fi

if [[ "$has_base" == true ]]; then
  image_list="$(find_image_dirs | grep -vxF 'images/base' || true)"
elif (( ${#changed[@]} > 0 )); then
  image_list="$(printf '%s\n' "${!changed[@]}" | sort -u)"
else
  image_list=""
fi

if [[ -z "$image_list" ]]; then
  log "change detection: has_base=$has_base, no images to build"
else
  log "change detection: has_base=$has_base, images to build:"
  while IFS= read -r image; do
    log "  - $image"
  done <<<"$image_list"
fi

echo "has_base=$has_base"
echo "images=$(images_json "$image_list")"
