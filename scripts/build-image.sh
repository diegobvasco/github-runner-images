#!/usr/bin/env bash
# Build (and optionally push/save) a single runner image.
#
# With --push the image is built with buildx, using the GitHub Actions cache
# (as configured by docker/setup-buildx-action) and pushed to the registry;
# otherwise it is built with plain "docker build" and kept local.
#
# Usage: build-image.sh <context-dir> [options]
#   --tag <suffix>     Image tag suffix (default: derived from the context
#                      directory, e.g. images/php/8.4 -> php84)
#   --push             Build with buildx + GHA cache and push (requires a
#                      prior registry login)
#   --save <file>      After building, save the image as a gzipped tar
#   --load <file>      Before building, load an image from a gzipped tar
#   --cache-scope <s>  GHA cache scope (default: the tag suffix)
#   --dry-run          Print the commands without running them
#   -h, --help         Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() { sed -n '/^# Usage:/,/^$/s/^# \?//p' "$0" >&2; }

context=""
tag=""
push=false
save=""
load=""
scope=""
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) [[ $# -ge 2 ]] || die "--tag requires a value"; tag="$2"; shift 2 ;;
    --push) push=true; shift ;;
    --save) [[ $# -ge 2 ]] || die "--save requires a file"; save="$2"; shift 2 ;;
    --load) [[ $# -ge 2 ]] || die "--load requires a file"; load="$2"; shift 2 ;;
    --cache-scope) [[ $# -ge 2 ]] || die "--cache-scope requires a value"; scope="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *)
      [[ -z "$context" ]] || die "unexpected extra argument: $1"
      context="$1"; shift ;;
  esac
done

if [[ -z "$context" ]]; then
  usage
  exit 1
fi
[[ -d "$context" ]] || die "context directory not found: $context"
[[ -f "$context/Dockerfile" ]] || die "no Dockerfile in: $context"

if [[ "$dry_run" == false ]]; then
  require_tools docker
fi

if [[ -z "$tag" ]]; then
  tag="$(image_tag_for_path "$context")"
fi
ref="$(image_repository):$tag"
scope="${scope:-$tag}"

run() {
  log "+ $*"
  if [[ "$dry_run" == false ]]; then
    "$@"
  fi
}

log "building $ref (context: $context)"

if [[ -n "$load" ]]; then
  [[ -f "$load" ]] || die "--load file not found: $load"
  run docker load --input "$load"
fi

if [[ "$push" == true ]]; then
  run docker buildx build "$context" \
    --tag "$ref" \
    --cache-from "type=gha,scope=$scope" \
    --cache-to "type=gha,scope=$scope,mode=max" \
    --push
else
  run docker build --tag "$ref" "$context"
fi

if [[ -n "$save" ]]; then
  log "+ docker save $ref | gzip > $save"
  if [[ "$dry_run" == false ]]; then
    docker save "$ref" | gzip > "$save"
  fi
fi

log "done: $ref"
