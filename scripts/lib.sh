#!/usr/bin/env bash
# Shared helpers for the image build scripts.
#
# Convention: functions that produce data write to stdout; log messages go to
# stderr, so a script's stdout can be piped (e.g. into "$GITHUB_OUTPUT").

# The empty git tree, used as diff base when no meaningful base commit exists
# (first push, manual dispatch). Diffing against it lists every file, which
# yields a full build.
EMPTY_TREE_SHA="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
ZERO_SHA="0000000000000000000000000000000000000000"

log() { printf '%s\n' "$*" >&2; }
warn() { log "warning: $*"; }
die() { log "error: $*"; exit 1; }

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
  done
}

git_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
  printf '%s\n' "$root"
}

# normalize_base <base> <head>
# Print the commit to diff against: <base>, or the empty tree when <base> is
# empty, all-zero, or equal to <head> (nothing meaningful to diff).
normalize_base() {
  local base="${1:-}" head="${2:?normalize_base: missing head}"
  if [[ -z "$base" || "$base" == "$ZERO_SHA" || "$base" == "$head" ]]; then
    printf '%s\n' "$EMPTY_TREE_SHA"
  else
    printf '%s\n' "$base"
  fi
}

# image_tag_for_path <dir>
# Derive the image tag from its directory: images/php/8.4 -> php84.
image_tag_for_path() {
  local dir="$1"
  dir="${dir#*/images/}"
  dir="${dir#images/}"
  dir="${dir//\//}"
  [[ -n "$dir" ]] || die "cannot derive an image tag from '$1'"
  printf '%s\n' "$dir"
}

# find_image_dirs
# List every directory under images/ that contains a Dockerfile (any depth),
# sorted. Images may live one or more levels below images/.
find_image_dirs() {
  (
    cd "$(git_root)" || exit 1
    find images -mindepth 1 -name Dockerfile -exec dirname {} \; | sort -u
  )
}

# image_dir_for_path <changed-file-path>
# Map a changed file to the image it belongs to: the nearest ancestor
# directory (walking up to images/) that contains a Dockerfile. Prints
# nothing and returns 1 when the file is not part of any image.
image_dir_for_path() {
  local file="$1" dir
  dir="$(dirname "$file")"
  while [[ "$dir" == images/* ]]; do
    if [[ -f "$dir/Dockerfile" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# detect_owner
# Repository owner: GITHUB_REPOSITORY_OWNER, then GITHUB_REPOSITORY, then the
# origin remote URL.
detect_owner() {
  local owner="${GITHUB_REPOSITORY_OWNER:-}" url
  if [[ -z "$owner" && -n "${GITHUB_REPOSITORY:-}" ]]; then
    owner="${GITHUB_REPOSITORY%%/*}"
  fi
  if [[ -z "$owner" ]]; then
    url="$(git remote get-url origin 2>/dev/null || true)"
    url="${url%.git}"
    owner="$(printf '%s' "$url" | awk -F'[/:]' '{print $(NF-1)}')"
  fi
  [[ -n "$owner" ]] || die "cannot determine repository owner; set GITHUB_REPOSITORY_OWNER"
  printf '%s\n' "$owner"
}

# image_repository
# Full image repository, e.g. ghcr.io/diegobvasco/github-runner.
# Override with REGISTRY and IMAGE_REPOSITORY when needed.
image_repository() {
  local owner
  owner="$(detect_owner)"
  printf '%s/%s\n' "${REGISTRY:-ghcr.io}" "${owner}/${IMAGE_REPOSITORY:-github-runner}"
}

# images_json <newline-separated image dirs>
# Encode as {"path": [...]} for the build matrix. Always prints valid JSON,
# even for an empty list.
images_json() {
  python3 -c 'import json, sys; print(json.dumps({"path": [line for line in sys.stdin.read().splitlines() if line]}))' <<<"$1"
}

# ghcr_layer_ids <repo> <ref>
# Print the rootfs layer digests (diff_ids) of the linux/amd64 image behind a
# GHCR tag, using an anonymous pull token.
ghcr_layer_ids() {
  local repo="$1" ref="$2"
  python3 - "$repo" "$ref" <<'PY'
import json
import sys
import urllib.request

repo, ref = sys.argv[1], sys.argv[2]
accept = ", ".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])


def get_json(url, accept_header=None):
    request = urllib.request.Request(url)
    if accept_header:
        request.add_header("Accept", accept_header)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


token_request = urllib.request.Request(
    f"https://ghcr.io/token?scope=repository:{repo}:pull&service=ghcr.io"
)
with urllib.request.urlopen(token_request, timeout=60) as response:
    token = json.load(response)["token"]


def fetch(url, accept_header=None):
    request = urllib.request.Request(url)
    request.add_header("Authorization", f"Bearer {token}")
    if accept_header:
        request.add_header("Accept", accept_header)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


index = fetch(f"https://ghcr.io/v2/{repo}/manifests/{ref}", accept)

digest = next(
    (
        m["digest"]
        for m in index.get("manifests", [])
        if m.get("platform", {}).get("os") == "linux"
        and m.get("platform", {}).get("architecture") == "amd64"
    ),
    None,
)

if digest:
    media_type = next(
        m["mediaType"] for m in index["manifests"] if m["digest"] == digest
    )
    manifest = fetch(f"https://ghcr.io/v2/{repo}/manifests/{digest}", media_type)
else:
    # No index: the response itself is a single-platform manifest.
    manifest = index

config_digest = manifest["config"]["digest"]
config = fetch(f"https://ghcr.io/v2/{repo}/blobs/{config_digest}")

for diff_id in config["rootfs"]["diff_ids"]:
    print(diff_id)
PY
}
