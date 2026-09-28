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
build_files/main.sh        runs every NN-*.sh below, in order, then cleans up
build_files/10-*.sh        numbered customisation scripts
build_files/20-*.sh
.gitlab-ci.yml             build + publish to the GitLab container registry
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

Available tags:

| Tag | Meaning |
| --- | --- |
| `latest` | most recent successful build of the default branch |
| `44` | Fedora version (tracks `BASE_IMAGE_TAG`) |
| `<commit sha>` | exact build, for rolling back |

## CI

Pipelines run on the default branch and on schedules:

1. **build** — `podman build`, tagging `latest`, the Fedora version, and the
   commit SHA.
2. **publish** — pushes all three tags to `$CI_REGISTRY/$CI_PROJECT_PATH`.

> **Runner requirement:** both jobs must run on the *same* shell executor.
> `publish` re-tags the image that `build` left in the local podman store, so
> a Docker-executor runner (fresh container per job) will fail here.

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
