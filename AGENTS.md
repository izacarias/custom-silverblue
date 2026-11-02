# AGENTS.md

Custom Fedora Silverblue bootc image ("Bluefin Classic DX-like, minus the
branding"): stock `quay.io/fedora-ostree-desktops/silverblue` base + codecs,
utilities, dev tooling, QEMU/libvirt. No application code. The image build is
the test suite. Deeper background: `README.md`; architecture detail:
`CLAUDE.md`.

## Commands

```bash
podman build --file Containerfile --tag custom-silverblue:latest .   # the real check
bash -n build_files/*.sh ci/*.sh                                     # cheap syntax check
git submodule update --init --recursive   # after a branch switch: a submodule
                                           # added on another branch lands as an
                                           # empty dir and the build's COPY fails
```

Success = `build_files/99-verify.sh` passes (runs inside the build) and
`bootc container lint` is clean at the end of `Containerfile`. Build residue
in `/var`, `/run` or caches fails the lint; `build_files/main.sh` cleanup
exists for exactly that reason — keep it.

## Structure

- `build_files/main.sh` runs `build_files/[0-9]*.sh` in lexical order. To add
  a customisation, drop in `NN-name.sh`; the whole directory is bind-mounted
  from the `ctx` stage, so no Containerfile change is needed. Scripts run as
  root and use the repo's `set -ouex pipefail` convention — don't "fix" it to
  `set -euo pipefail`.
- Script order is load-bearing: `10-repos.sh` registers every third-party repo
  before later scripts install from it; `35-trim.sh` removes `podman-docker`
  before `40-dev-tooling.sh` installs `docker-ce` (hard conflict).
- `Containerfile` has build stages for the four `extensions/` **git
  submodules** (dash-to-dock, blur-my-shell, gnome-rounded-blur,
  status-tray). CI must check out submodules recursively. The dash-to-dock
  stage's `VERSION=NNN`
  must match the submodule's release tag when bumping it. gnome-rounded-blur
  must be new enough for the shipped mutter: v1.0.2+ auto-detects the
  `libmutter-*.pc` name (renamed at GNOME 51), older pins hardcode
  `libmutter-18` and fail with `Dependency "libmutter-18" not found`.
  status-tray is pure JS: its stage only copies `src/` and runs
  `glib-compile-schemas`; its `metadata.json` `shell-version` must cover the
  shipped GNOME Shell.
- CI: `.gitlab-ci.yml` and `.github/workflows/build-image.yml` are thin
  wrappers around `ci/build-image.sh` / `ci/build-iso.sh`. Change build logic
  in `ci/*.sh`, never in only one CI file. Both publish one image with tags
  `latest`, `<fedora version>`, `<YYYYMMDD>-<5-char sha>`.
- `Containerfile.rechunk` (RECHUNK) and `Containerfile.installer` (BUILD_ISO)
  are optional CI post-processing (chunkah layer re-split; Anaconda ISO via
  bootc-image-builder, pinned as `BIB_IMAGE`).

## Hard constraints (each has bitten before)

- `20-multimedia.sh` must stay **one `dnf install` with `--allowerasing`** for
  the codec packages (`@multimedia ffmpeg libavcodec-freeworld
  intel-media-driver`). Splitting them or dropping `--allowerasing` makes
  dnf5 pick the i686 `libavcodec-freeworld` and the solve fails after
  pulling ~100 i686 packages. Unrelated packages go in other scripts.
- The `matches only excluded packages` warning from
  `--exclude=PackageKit-gstreamer-plugin` is expected; keep the exclusion.
- `ARG BASE_IMAGE_TAG="NN"` in the Containerfile must keep its exact line
  format — both CI systems extract the Fedora version from it with `sed`.
- `/opt` becomes a symlink to `/var/opt` in the final image. Anything a script
  installs into `/opt` needs the tmpfiles.d workaround pattern from
  `70-cisco-vpn.sh`.
- Firefox and `keepassxc` are deliberately native RPMs (KeePassXC browser
  integration needs native messaging); `35-trim.sh` must keep them exempt
  from the Flatpak-only trim and `99-verify.sh` asserts both directions
  (present/absent packages). Add new guarantees there.
- Docker/libvirt group membership happens at first boot via
  `dev-groups.service` (created in `50-virtualization.sh`) because the build
  has no regular users. It is idempotent; don't move it into the build.
- GitHub release assets are capped at 2 GiB, so `ci/build-iso.sh` uploads the
  ~5 GB ISO split into parts for GitHub and whole for GitLab's generic
  package registry. Registry refs are lowercased in `ci/*.sh` (GHCR requires
  it) — don't re-add case handling elsewhere.

## Conventions

- Commit style is conventional-ish (`feat:`, `fix:`, `ci:`) on `feat/*` or
  `ci/*` branches merged into `main`.
- Keep `README.md` and `CLAUDE.md` in sync when renaming scripts or changing
  the CI flow; they are the human docs and are already referenced from both
  CI systems' comments.
