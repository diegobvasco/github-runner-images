#!/usr/bin/env bash
# Check whether our published base image is out of date with the upstream
# actions-runner image, by comparing the rootfs layer digests (diff_ids) of
# the linux/amd64 images on GHCR.
#
# Prints GitHub Actions outputs on stdout (logs go to stderr):
#   changed=true|false
#   fingerprint=<sha256 of the upstream layer ids>
#
# Usage: check-upstream.sh [--owner <owner>] [--force]
#   --owner <owner>  Image owner (default: GITHUB_REPOSITORY_OWNER or the
#                    origin remote)
#   --force          Report changed=true even when upstream is in sync
#   -h, --help       Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

require_tools python3

UPSTREAM_REPO="actions/actions-runner"
UPSTREAM_REF="latest"
OURS_REF="base"

usage() { sed -n '/^# Usage:/,/^$/s/^# \?//p' "$0" >&2; }

owner="${OWNER:-}"
force="${FORCE:-false}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) [[ $# -ge 2 ]] || die "--owner requires a value"; owner="$2"; shift 2 ;;
    --force) force=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$owner" ]] || owner="$(detect_owner)"
ours_repo="${owner}/${IMAGE_REPOSITORY:-github-runner}"

upstream_layers="$(ghcr_layer_ids "$UPSTREAM_REPO" "$UPSTREAM_REF")"
if [[ -z "$upstream_layers" ]]; then
  die "could not read layers of ghcr.io/${UPSTREAM_REPO}:${UPSTREAM_REF}"
fi

# Empty output means the published base image does not exist yet.
ours_layers="$(ghcr_layer_ids "$ours_repo" "$OURS_REF" 2>/dev/null || true)"

changed=false
if [[ -z "$ours_layers" ]]; then
  log "::notice::ghcr.io/${ours_repo}:${OURS_REF} not found; scheduling a full build"
  changed=true
else
  upstream_count="$(wc -l <<<"$upstream_layers")"
  ours_prefix="$(head -n "$upstream_count" <<<"$ours_layers")"
  if [[ "$ours_prefix" != "$upstream_layers" ]]; then
    changed=true
  fi
fi

if [[ "$force" == true ]]; then
  changed=true
fi

fingerprint="$(printf '%s\n' "$upstream_layers" | sha256sum | cut -d' ' -f1)"

log "Upstream layers: $(wc -l <<<"$upstream_layers")"
if [[ -n "$ours_layers" ]]; then
  log "Published ${OURS_REF} layers: $(wc -l <<<"$ours_layers")"
fi
log "Upstream fingerprint: $fingerprint"

echo "changed=$changed"
echo "fingerprint=$fingerprint"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  if [[ "$changed" == true ]]; then
    {
      echo "### ⬆️ Upstream runner image updated"
      echo ""
      echo "Base layers of \`ghcr.io/${ours_repo}:${OURS_REF}\` no longer match \`ghcr.io/${UPSTREAM_REPO}:${UPSTREAM_REF}\` (fingerprint \`${fingerprint:0:12}\`). Dispatching \`build.yaml\` to rebuild base and all dependent images."
    } >>"$GITHUB_STEP_SUMMARY"
  else
    {
      echo "### ✅ Upstream runner image in sync"
      echo ""
      echo "\`ghcr.io/${ours_repo}:${OURS_REF}\` already matches \`ghcr.io/${UPSTREAM_REPO}:${UPSTREAM_REF}\` (fingerprint \`${fingerprint:0:12}\`)."
    } >>"$GITHUB_STEP_SUMMARY"
  fi
fi
