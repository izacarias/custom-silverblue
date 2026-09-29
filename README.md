# custom-silverblue

A custom [Fedora Silverblue](https://fedoraproxy.org/en/silverblue/) image,
built from the official `quay.io/fedora-ostree-desktops/silverblue` base and
extended with RPM Fusion codecs. The base image tag is defined by
`BASE_IMAGE_TAG` in the [`Containerfile`](Containerfile) and is the single
source of truth for the Fedora release.

## What's added on top of stock Silverblue

- **RPM Fusion** free + nonfree repositories
- **Full FFmpeg** (`ffmpeg`, with `libx264`, `libx265`, `libvpx-vp9` and
  `nvenc` encoders) replacing Fedora's encoder-less `ffmpeg-free`
- **`libavcodec-freeworld`** replacing `libavcodec-free`
- The **`@multimedia`** group, minus `PackageKit-gstreamer-plugin`
- **`intel-media-driver`** for Intel VAAPI

Everything else — desktop, apps, Flatpak setup — is untouched upstream
Silverblue.

## Layout

```
Containerfile              multi-stage build; runs build_files/main.sh, then
                           `bootc container lint` to validate the result
Containerfile.rechunk      optional chunkah re-splitting of the built image
                           into content-based layers (CI: RECHUNK variable)
Containerfile.installer    Anaconda installer environment for the optional
                           installation ISO (CI: BUILD_ISO variable)
build_files/main.sh        runs every NN-*.sh below, in order, then cleans up
build_files/10-*.sh        numbered customisation scripts
build_files/20-*.sh
.gitlab-ci.yml             image-build: build the image and push it to the
                           GitLab container registry; iso-build: optional
                           installation ISO
```

## Building locally

```bash
podman build --file Containerfile --tag custom-silverblue:latest .
```

The build ends with `bootc container lint`, so a successful build means the
image passed all 14 checks with zero warnings.

## Adding packages

Drop a new script into `build_files/` with a two-digit prefix. It is picked up
automatically — no `Containerfile` change required, because the whole
directory is bind-mounted from the `ctx` stage.

```bash
cat > build_files/30-dev-tools.sh <<'EOF'
#!/bin/bash
set -ouex pipefail
dnf install -y git tmux htop jq ripgrep
EOF
```

Scripts run as root, so `sudo` is unnecessary.

### Keep related packages in one transaction

The multimedia script **must** stay a single `dnf` invocation with
`--allowerasing`. The base image ships `libavcodec-free`/`ffmpeg-free`, which
conflict with RPM Fusion's replacements; without `--allowerasing` dnf5 avoids
the conflict by installing the **i686** build of `libavcodec-freeworld` —
useless on x86_64, and it drags in ~100 i686 packages before the solve fails.
Splitting the packages across separate `dnf` calls reintroduces the same bug.

## Installing the image

The image is published to your GitLab container registry as
`$CI_REGISTRY_IMAGE` (`<registry>/<project path>`).

```bash
# bootc
sudo bootc switch <registry>/<project path>:latest

# or, on rpm-ostree
sudo rpm-ostree rebase ostree-unverified-registry:<registry>/<project path>:latest
```

> [!NOTE]
> With the CI `RECHUNK` option enabled (see
> [Content-based layers](#content-based-layers-optional)), the published image
> is a *plain* bootc image: `bootc switch` works as usual, but the
> `rpm-ostree rebase` path may no longer work, because the ostree repository
> is stripped from the image.

Available tags:

| Tag | Meaning |
| --- | --- |
| `latest` | most recent successful build of the default branch |
| `44` | Fedora version (tracks `BASE_IMAGE_TAG`) |
| `<commit sha>` | exact build, for rolling back |

## CI

Pipelines run on the default branch and on schedules as a **single job** that
builds the image and pushes it. There is no separate publish stage, so nothing
depends on the runner's podman store surviving between jobs. An opt-in second
job builds an installation ISO ([below](#installation-iso-optional)).

Tags pushed to `$CI_REGISTRY_IMAGE` are listed under
[Installing the image](#installing-the-image):

Every push records its digest to an `image-digests.txt` job artifact, and the
image carries `org.opencontainers.image.*` provenance labels (revision,
source, created).

### Content-based layers (optional)

Set the `RECHUNK` variable to `true` — Run pipeline → variables, or in a
schedule's variables — and the job re-splits the finished image into
content-based layers with [chunkah](https://github.com/coreos/chunkah)
(`Containerfile.rechunk`) before pushing. Layers then follow the image's
content (roughly, per package) instead of the `Containerfile`'s `RUN`s, so
unchanged packages land in unchanged layers and client updates only pull what
actually changed.

The default is `false`, which leaves the image exactly as the `Containerfile`
builds it. When enabled:

- The result is a **plain bootc image**: following chunkah's recipe for
  ostree-based images, the base's ostree repository (`/sysroot`) and the
  stale `ostree.*`/`rpmostree.*` labels are stripped (see the note under
  [Installing the image](#installing-the-image)). The image config
  (`CMD`, `containers.bootc=1`, provenance labels) is preserved.
- Layers are capped at 128 (`--max-layers`); with fewer layers the packing
  gets coarser, with more, pull overhead grows.
- Costs: one extra pass over the ~6 GB image (~3 min) and ~6 GB of scratch
  space on the runner. It runs once; all three tags are then re-pointed at
  the chunked image before the push.
- chunkah is pinned to `quay.io/coreos/chunkah:v0.7.0` in
  `Containerfile.rechunk`; bump the tag there to update.

### Installation ISO (optional)

Set the `BUILD_ISO` variable to `true` — Run pipeline → variables, or a
schedule's variables — and a second stage (`iso-build`) builds an **Anaconda
installation ISO** from the image `image-build` just pushed, then uploads it
to the generic package registry:

```
<project URL>/-/packages/generic/installer-iso/<commit sha>/custom-silverblue-<fedora version>-<commit sha>.iso
```

A `.sha256` is uploaded next to it, the download URL is printed in the job
log, and the checksum plus the osbuild manifest are kept as job artifacts.
Re-running the job replaces the previous upload for the same commit.

Nothing else changes without the variable: `iso-build` is not created at all
unless `BUILD_ISO=true`, so ordinary builds stay a single job.

How it works:

1. [`Containerfile.installer`](Containerfile.installer) builds the *installer
   environment* — the image that was just published, plus Anaconda
   (`anaconda`, `anaconda-dracut`, `anaconda-install-env-deps`, lorax
   templates, …). It is built from the pushed image and is never pushed
   itself.
2. [bootc-image-builder](https://github.com/osbuild/image-builder) (osbuild,
   pinned by digest as `BIB_IMAGE`) packs that environment into an ISO and
   embeds the published image as the payload Anaconda installs. Both images
   are read from the runner's own container store, which is why the job pulls
   the image back from the registry first instead of relying on
   `image-build`'s local tags.
3. The ISO is checksummed and uploaded to the generic package registry with
   `$CI_JOB_TOKEN` — job artifacts would be far too small (~5 GB ISO).

**Runner requirements.** The job verifies these up front and fails with a
`::error::` annotation rather than an hour into the build:

| Requirement | Why |
| --- | --- |
| rootful podman (runner as root, or passwordless `sudo`) | bootc-image-builder refuses to run rootless, and buildah has to use the same store |
| `podman` next to `buildah` | bootc-image-builder is executed with it |
| ~30 GiB free next to the container store | both images, osbuild's store and the ISO live side by side |
| `osbuild-selinux` installed while SELinux is enforcing | bootc-image-builder runs privileged, so the host's policy applies inside |

The first run pulls `BIB_IMAGE` (~1.5 GB); later runs keep it warm.

**One-time runner setup.** The runner user must be able to run `podman` and
`buildah` without a password prompt (the job probes for it and fails with a
`::error::` naming this file otherwise):

```bash
# /etc/sudoers.d/gitlab-runner  (mode 0440)
gitlab-runner ALL=(root) NOPASSWD: /usr/bin/podman, /usr/bin/buildah
```

Everything the job does with containers goes through that `sudo`, which is
also what keeps buildah and the bib podman on the same container store
(`id -u` root needs no configuration at all).

Two things to know about the resulting ISO:

- Anaconda runs in **text mode**: bootc-image-builder hardcodes the
  `inst.text` kernel option for the `bootc-installer` image type.
- The payload is installed offline from the ISO, but the generated kickstart
  then finishes with `bootc switch --mutate-in-place --transport registry
  <payload ref>` — Anaconda pulls `$CI_REGISTRY_IMAGE:<commit sha>` at the
  very end to point the installed system at its update source. That last step
  needs network access, and if the registry image is not pullable
  anonymously, also registry credentials; without them it reports an error
  after the payload is already installed.

### Runner

The job shells out to `podman`, so it needs a **shell executor** — the runner
is tagged `tubs-kns`. `iso-build` additionally needs rootful podman
(see [Installation ISO](#installation-iso-optional)).

### Registry authentication — nothing to configure

GitLab injects credentials for its built-in container registry automatically,
so there is no secret to create:

| Variable | Purpose |
| --- | --- |
| `CI_REGISTRY` | registry host |
| `CI_REGISTRY_IMAGE` | image path (`<registry>/<project path>`) |
| `CI_REGISTRY_USER` | `gitlab-ci-token`, scoped to this project |
| `CI_REGISTRY_PASSWORD` | per-job token, auto-rotated, already masked |

The job checks `CI_REGISTRY` up front and fails with a `::error::` annotation
if it is empty, rather than failing later at push time.

**Prerequisites:**

1. Container registry enabled at the instance level on the GitLab server.
2. Project → Settings → General → Visibility, project features and
   permissions → **Container registry** enabled.

**Fallback — scoped token.** If the built-in credentials are not usable,
create a project access token (or deploy token) with the `write_registry`
scope, store it as a **Masked + Protected** CI/CD variable, and point the two
variable references in `.gitlab-ci.yml` at it. Marking it *Protected* is safe
here, because pipelines only run on the default branch, which is protected by
default.

## Notes

- The stock Silverblue image already ships 14 of the 16 packages in the
  `multimedia` group, so `@multimedia` on its own adds almost nothing —
  RPM Fusion is what actually delivers the codecs.
- There is **no `ffmpeg` in rpmfusion-nonfree**; the full build lives in
  `rpmfusion-free`, while nonfree contributes `intel-media-driver`.
- Fedora already ships `libva-intel-media-driver` (newer), and libva searches
  both `dri/` and `dri-nonfree/`, so `intel-media-driver` is redundant but
  harmless.
- `--exclude=PackageKit-gstreamer-plugin` prints a
  `matches only excluded packages` warning under dnf5. It is harmless and
  the exclusion does apply.
