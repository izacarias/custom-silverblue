# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A custom Fedora Silverblue bootc/OCI image in the spirit of Bluefin Classic DX: `quay.io/fedora-ostree-desktops/silverblue` plus RPM Fusion codecs, system utilities, developer tooling and a QEMU/libvirt VM stack, without Bluefin branding. There is no application code. The checks are `build_files/99-verify.sh` (runs during the build) and `bootc container lint` at the end of `Containerfile` — a successful image build is the test suite.

## Commands

```bash
# Build the image locally (same Containerfile CI uses; CI runs `buildah build`)
podman build --file Containerfile --tag custom-silverblue:latest .

# Quick syntax check of the build and CI scripts (does not run them)
bash -n build_files/*.sh ci/*.sh
```

A build only counts as successful if `99-verify.sh` passes and `bootc container lint` is clean at the end of `Containerfile`. Any build residue left in `/var`, `/run` or caches will make the lint fail.

## Architecture

- **`Containerfile`**: a `ctx` scratch stage holds `build_files/`, which is bind-mounted into the base stage and run through `build_files/main.sh`. The scripts are never copied into the final image. `ARG BASE_IMAGE_TAG="NN"` is the single source of truth for the Fedora release; both CI systems parse it with `sed` to produce the `<fedora version>` image tag, so keep the line format intact.
- **`build_files/main.sh`** runs every `build_files/[0-9]*.sh` in lexical order (so `99-verify.sh` runs last), then deletes dnf/rpm-ostree caches, logs and `/var/lib/dnf`, and `rmdir`s any `/var` subdirectories it emptied. This is what keeps `bootc container lint` clean. To add a customisation, drop in a new `NN-name.sh`; no Containerfile change is needed. Scripts run as root and start with `set -ouex pipefail`.
- **Script order matters**: `10-repos.sh` registers every third-party repo (RPM Fusion, VS Code, Docker CE, Tailscale, COPRs) before anything installs from them; `20-multimedia.sh` does the codec swap; `35-trim.sh` removes `podman-docker` before `40-dev-tooling.sh` installs `docker-ce` (they conflict).
- **Homebrew** comes from `ghcr.io/ublue-os/brew:latest`. The Containerfile copies its `/system_files` in with `COPY --from` and presets `brew-setup.service`, `brew-update.timer` and `brew-upgrade.timer`. On first boot, `brew-setup.service` unpacks `/usr/share/homebrew.tar.zst` into `/home/linuxbrew/.linuxbrew` and chowns it to UID 1000.
- **GNOME extensions** are git submodules under `extensions/`, each pinned to an upstream release tag and built in its own Containerfile stage. CI fetches them via `GIT_SUBMODULE_STRATEGY: recursive` (GitLab) or `submodules: recursive` (GitHub). `60-gnome-extensions.sh` enables them for all users via a gschema override.
  - `extensions/dash-to-dock`: the `dash-to-dock` stage runs `make install DESTDIR=/out VERSION=NNN` and the result is copied into `/usr`. When bumping the submodule tag, bump `VERSION=` too.
  - `extensions/blur-my-shell`: the `blur-my-shell` stage runs upstream `make build` (`gnome-extensions pack`) and unzips the result into `/usr/share/gnome-shell/extensions/blur-my-shell@aunetx`.
  - `extensions/gnome-rounded-blur`: the `rounded-blur` stage runs the meson build that upstream's `rounded_blur_build.sh` does. Only `libblur-effect-1.0.so*` and `Blur-1.0.typelib` are copied in; Blur My Shell loads them as `gi://Blur`. Both of these stages build `FROM ${BASE_IMAGE_REF}` so `mutter-devel` matches the shipped mutter. Since v1.0.2 upstream auto-detects the `libmutter-*.pc` name (mutter renamed its pkg-config files at GNOME 51: `libmutter-18` → `libmutter-51`) and no longer uses `clutter_get_default_backend()` (dropped in mutter 51). When Fedora moves to a new GNOME/mutter, first check that the pinned tag is new enough for that mutter — older pins fail exactly at `Dependency "libmutter-18" not found`.
- **CI is two thin wrappers around `ci/build-image.sh` and `ci/build-iso.sh`** (shared so GitHub and GitLab cannot drift): `.gitlab-ci.yml` publishes to `$CI_REGISTRY_IMAGE` (tags `latest`, `<fedora version>`, `<YYYYMMDD>-<5-char sha>`), `.github/workflows/build-image.yml` to `ghcr.io/<owner>/<repo>` (the script lowercases the ref). Shell executor on GitLab (runner tag `tubs-kns`), GitHub-hosted ubuntu runners with apt-installed podman/buildah. `iso-build` needs rootful podman/buildah through passwordless sudo (GitHub runners have that; GitLab needs the sudoers entry described in the README).
- **`Containerfile.rechunk`** (`RECHUNK`, default true): re-splits the built image into content-based layers with chunkah. The result is a plain bootc image, so `rpm-ostree rebase` may stop working.
- **`Containerfile.installer`** (`BUILD_ISO`, default true): an Anaconda installer environment (the bootc `bootc-installer` recipe Bluefin Classic uses) that bootc-image-builder (pinned by digest as `BIB_IMAGE`) turns into an ISO. GitLab uploads it whole to the generic package registry; GitHub release assets are capped at 2 GiB, so `ci/build-iso.sh` splits the ~5 GB ISO into parts before uploading to a `installer-iso/<tag>` release.

## Gotchas

- `20-multimedia.sh` **must stay a single `dnf install` with `--allowerasing`**. The base image ships `ffmpeg-free`/`libavcodec-free`. If the codec packages are split up or `--allowerasing` is dropped, dnf5 picks the i686 `libavcodec-freeworld` and the solve fails after pulling in about 100 i686 packages. Unrelated packages belong in other scripts.
- The `matches only excluded packages` warning from `--exclude=PackageKit-gstreamer-plugin` is expected and harmless.
- `/opt` is replaced with a symlink to `/var/opt` after the scripts run. Anything a script installs into `/opt` won't survive as-is; `70-cisco-vpn.sh` shows the tmpfiles.d workaround pattern.
- Firefox and `keepassxc` are **deliberately** native RPMs (KeePassXC browser integration via native messaging) and `35-trim.sh` must keep exempting them from the Flatpak-only trim. `99-verify.sh` asserts this.
- Docker/libvirt group membership is granted at first boot by `dev-groups.service` (`50-virtualization.sh`), because the build has no regular users. It is idempotent; don't "fix" it into the build.
- Commit style is conventional-ish (`feat:`, `fix:`, `ci:`) on `feat/*` or `ci/*` branches merged into `main`.
