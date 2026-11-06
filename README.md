# github-runner-images

Custom GitHub Actions runner images, built on top of the official
[`actions/actions-runner`](https://github.com/actions/runner-images) image and
published to GHCR. Build orchestration lives in versioned shell scripts, so the
same logic runs in CI and locally.

## Published images

All images are published to `ghcr.io/diegobvasco/github-runner` (amd64):

| Tag | Source | Contents |
| --- | --- | --- |
| `base` | `images/base` | Official runner image + `git`, `curl`, `unzip`, `sudo`, `ca-certificates`, `jq`, `make`, `build-essential`, `docker.io` |
| `php8.4` | `images/php/8.4` | PHP 8.4 (mbstring, curl, xml, pcov, mysql, sqlite3) + Composer |
| `php8.5` | `images/php/8.5` | PHP 8.5 (mbstring, curl, xml, pcov, mysql, sqlite3) + Composer |
| `phpmulti` | `images/php/multi` | PHP 8.1–8.6 via `update-alternatives`, wide extension set, Composer |

Dependent images build `FROM ghcr.io/diegobvasco/github-runner:base`, so the
base image is always built first.

## How builds decide what to build

Change detection lives in [`scripts/needs-build.sh`](scripts/needs-build.sh)
and works by diffing two commits:

| Changed | What gets built |
| --- | --- |
| Anything under `images/base/` | `base` **and every other image** (they all depend on it) |
| Files under an image directory | Only that image — found by walking up to the nearest ancestor directory containing a `Dockerfile`, at any depth (e.g. `images/foo/Dockerfile` or `images/php/8.4`) |
| Files without a `Dockerfile` ancestor (e.g. `images/NOTES.md`) | Nothing |
| Deleted image directory | Skipped safely |
| No meaningful base commit (first push, manual `workflow_dispatch`) | Everything (diff against the empty tree) |

The CI build order is: `prepare` (detection) → `build-base` → one matrix job
per dependent image.

- **Push to `main`** (only when `images/**` changes): build with
  `docker buildx`, GitHub Actions layer cache, push to GHCR.
- **Pull request** (only when `images/**` changes): build only — the base image
  is exported as a tar artifact and loaded into dependent jobs, so PRs test
  against the PR's own base, not the published one.

## Upstream drift detection

[`check-upstream.yaml`](.github/workflows/check-upstream.yaml) runs daily at
04:30 UTC. `scripts/check-upstream.sh` compares the rootfs layer digests
(`diff_ids`) of `ghcr.io/actions/actions-runner:latest` against the published
`:base`. When the upstream layers change (or `:base` doesn't exist yet), it
dispatches `build.yaml` to rebuild everything. Manual dispatches accept a
`force` input to rebuild regardless.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/needs-build.sh` | Print which images need building (`has_base=`, `images={"path":[…]}`) |
| `scripts/build-image.sh` | Build (and optionally push/save/load) a single image |
| `scripts/build.sh` | Build everything that needs building, base first |
| `scripts/check-upstream.sh` | Check the published base against the upstream runner image |
| `scripts/lib.sh` | Shared helpers (sourced by the above) |

Requirements: `bash`, `git`, `python3`; `docker` (with buildx for `--push`).
Data outputs go to stdout, logs to stderr, so scripts can be piped (e.g. into
`$GITHUB_OUTPUT`).

### Local usage

```bash
# Dry-run: see exactly what would be built right now
scripts/build.sh --dry-run

# Build incrementally (vs HEAD~1); pulls the published base if it's unchanged
scripts/build.sh

# Build everything and push (requires docker login ghcr.io)
scripts/build.sh --all --push

# Detection only
scripts/needs-build.sh --base HEAD~3 --head HEAD

# Single image
scripts/build-image.sh images/php/8.4 --dry-run
scripts/build-image.sh images/base --tag base --push

# Upstream check
scripts/check-upstream.sh --owner diegobvasco
```

Registry and image name can be overridden with `REGISTRY` and
`IMAGE_REPOSITORY` (defaults: `ghcr.io`, `github-runner`).

## Adding a new image

1. Create a directory with a `Dockerfile` anywhere under `images/` (one level,
   `images/my-image/Dockerfile`, or nested, `images/lang/version/Dockerfile`).
2. Base it on `ghcr.io/diegobvasco/github-runner:base` unless it *is* a new
   base.
3. That's it — the tag is derived from the path (`images/php/8.4` → `php8.4`),
   detection picks it up automatically, and it joins the build matrix.

## Using the images

```bash
docker pull ghcr.io/diegobvasco/github-runner:phpmulti
docker run -it --rm ghcr.io/diegobvasco/github-runner:phpmulti bash
```

The images contain the standard actions-runner layout (user `runner`), so they
can also back self-hosted runners.
