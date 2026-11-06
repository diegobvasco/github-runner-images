#!/usr/bin/env bash
# Build every image that needs building, base image first.
#
# Change detection is delegated to needs-build.sh and each image is built with
# build-image.sh. Locally this is a plain "docker build" per image; pass
# --push to build with buildx and push (requires a prior registry login).
#
# Usage: build.sh [--all] [--push] [--base <sha>] [--head <sha>] [--dry-run]
#   --all         Build every image, ignoring change detection
#   --push        Push the images after building
#   --base <sha>  Base commit for change detection (default: HEAD~1)
#   --head <sha>  Head commit for change detection (default: HEAD)
#   --dry-run     Print what would be built without running docker
#   -h, --help    Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_tools git python3

usage() { sed -n '/^# Usage:/,/^$/s/^# \?//p' "$0" >&2; }

select_args=()
run_args=()
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) select_args+=(--all); shift ;;
    --base) [[ $# -ge 2 ]] || die "--base requires a commit"; select_args+=(--base "$2"); shift 2 ;;
    --head) [[ $# -ge 2 ]] || die "--head requires a commit"; select_args+=(--head "$2"); shift 2 ;;
    --push) run_args+=(--push); shift ;;
    --dry-run) dry_run=true; run_args+=(--dry-run); shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

cd "$(git_root)"

detection="$("$SCRIPT_DIR/needs-build.sh" "${select_args[@]}")"
has_base="$(sed -n 's/^has_base=//p' <<<"$detection")"
images="$(sed -n 's/^images=//p' <<<"$detection")"
paths="$(python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)["path"]))' <<<"$images")"

if [[ "$has_base" == true ]]; then
  "$SCRIPT_DIR/build-image.sh" images/base --tag base "${run_args[@]}"
elif [[ -n "$paths" ]]; then
  # Base unchanged: make sure dependents can resolve their FROM image.
  base_ref="$(image_repository):base"
  if [[ "$dry_run" == true ]]; then
    log "+ docker pull $base_ref (base unchanged; ensuring it is available locally)"
  else
    log "pulling $base_ref (base unchanged in this run)"
    docker pull "$base_ref" || warn "could not pull $base_ref; continuing with any local copy"
  fi
fi

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  "$SCRIPT_DIR/build-image.sh" "$path" "${run_args[@]}"
done <<<"$paths"
