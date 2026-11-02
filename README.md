# custom-silverblue

A custom [Fedora Silverblue](https://fedoraproxy.org/en/silverblue/) image in
the spirit of **Bluefin Classic DX**: built directly on the official
`quay.io/fedora-ostree-desktops/silverblue` base — no Universal Blue layer in
between — with codecs, system utilities and developer tooling on top. No
Bluefin branding: the desktop stays stock Fedora. The base image tag is
defined by `BASE_IMAGE_TAG` in the [`Containerfile`](Containerfile) and is
the single source of truth for the Fedora release.

## What's added on top of stock Silverblue

- **RPM Fusion** free + nonfree repositories
- **Full FFmpeg** (`ffmpeg`, with `libx264`, `libx265`, `libvpx-vp9` and
  `nvenc` encoders) replacing Fedora's encoder-less `ffmpeg-free`,
  **`libavcodec-freeworld`** replacing `libavcodec-free`, the **`@multimedia`**
  group (minus `PackageKit-gstreamer-plugin`) and **`intel-media-driver`**
  for Intel VAAPI
- **System utilities** (modelled on Bluefin's base set): fish/zsh/tmux,
  fastfetch/glow/gum, borgbackup/restic/rclone, powertop/powerstat/iotop/
  lm_sensors, samba/winbind/krb5/sssd for AD login, Tailscale + WireGuard,
  printing (hplip, brlaser), fonts (Adwaita, JetBrains Mono, Cascadia,
  Nerd Fonts), gnome-tweaks, gsconnect, starship
- **Developer tooling** (modelled on Bluefin DX): Docker CE + compose/buildx,
  podman-compose/podman-tui/podman-machine, distrobox, flatpak-builder,
  VS Code, ghostty, bcc/bpftrace/bpftop/trace-cmd, git extras, p7zip,
  android-tools
- **Virtual machines** (Bluefin DX minus Cockpit/Incus): QEMU/KVM, libvirt,
  virt-manager/viewer/v2v, edk2-ovmf; users are added to the `docker` and
  `libvirt` groups at first boot
- **GNOME extensions**: Dash-to-Dock, Blur My Shell (with the
  gnome-rounded-blur mutter plugin) and Status Tray (AppIndicator /
  StatusNotifierItem system tray), enabled by default for all users
- **Homebrew** from `ghcr.io/ublue-os/brew` (setup/update units preset;
  unpacks on first boot)
- **Cisco Secure Client** VPN module (TU Braunschweig), with a tmpfiles.d
  workaround for the `/opt` symlink (see `build_files/70-cisco-vpn.sh`)

**Native application policy:** Fedora's own applications stay installed and
`keepassxc` is installed as an RPM next to native Firefox, so KeePassXC's
browser integration works over native messaging. Bluefin's Flatpak-only trim
is applied to everything else (`gnome-software`, `yelp`, `cosign`, …, see
`build_files/35-trim.sh`).

## Layout

```
Containerfile              multi-stage build; runs build_files/main.sh, then
                           `bootc container lint` to validate the result
Containerfile.rechunk      optional chunkah re-splitting of the built image
                           into content-based layers (CI: RECHUNK variable)
Containerfile.installer    Anaconda installer environment for the optional
                           installation ISO (CI: BUILD_ISO variable)
build_files/main.sh        runs every NN-*.sh below, in order, then cleans up
build_files/10-repos.sh    third-party repos + base image upgrade
build_files/20-multimedia.sh  codec swap (single dnf transaction!)
build_files/30-*.sh        system utilities (+ keepassxc)
build_files/35-trim.sh     Flatpak-only trim (Firefox/keepassxc exempt)
build_files/40-*.sh        developer tooling (Docker, VS Code, …)
build_files/50-*.sh        virtual machines (libvirt/QEMU)
build_files/60-*.sh        GNOME extension defaults
build_files/70-*.sh        Cisco Secure Client VPN
build_files/99-verify.sh   build-time assertions on the package set
ci/build-image.sh          image build + push, shared by both CI systems
ci/build-iso.sh            ISO build + publish, shared by both CI systems
.github/workflows/         GitHub Actions: image -> GHCR, ISO -> release
.gitlab-ci.yml             GitLab CI: image -> GitLab registry, ISO -> generic
                           package registry
```

## Building locally

```bash
podman build --file Containerfile --tag custom-silverblue:latest .
```

The build ends with `bootc container lint`, so a successful build means the
image passed all checks with zero warnings.

## Adding packages

Drop a new script into `build_files/` with a two-digit prefix. It is picked up
automatically — no `Containerfile` change required, because the whole
directory is bind-mounted from the `ctx` stage.

```bash
cat > build_files/80-my-tools.sh <<'EOF'
#!/bin/bash
set -ouex pipefail
dnf install -y git tmux htop jq ripgrep
EOF
```

Scripts run as root, so `sudo` is unnecessary. Run `build_files/99-verify.sh`
assertions against anything you want guaranteed in the image.

### Keep related packages in one transaction

`20-multimedia.sh` **must** stay a single `dnf` invocation with
`--allowerasing`. The base image ships `libavcodec-free`/`ffmpeg-free`, which
conflict with RPM Fusion's replacements; without `--allowerasing` dnf5 avoids
the conflict by installing the **i686** build of `libavcodec-freeworld` —
useless on x86_64, and it drags in ~100 i686 packages before the solve fails.
Splitting the codec packages across separate `dnf` calls reintroduces the same
bug. Unrelated packages belong in the other scripts.

## Installing the image

Each CI publishes the same image under its own registry — GitLab
(`$CI_REGISTRY_IMAGE`) or GitHub (`ghcr.io/<owner>/<repo>`).

```bash
# bootc
sudo bootc switch <registry>/<project path>:latest

# or, on rpm-ostree
sudo rpm-ostree rebase ostree-unverified-registry:<registry>/<project path>:latest
```

> [!NOTE]
> With the `RECHUNK` option enabled (see
> [Content-based layers](#content-based-layers-optional)), the published image
> is a *plain* bootc image: `bootc switch` works as usual, but the
> `rpm-ostree rebase` path may no longer work, because the ostree repository
> is stripped from the image.

Available tags:

| Tag | Meaning |
| --- | --- |
| `latest` | most recent successful build of the default branch |
| `<fedora version>` | Fedora release (tracks `BASE_IMAGE_TAG`) |
| `<YYYYMMDD>-<5-char sha>` | exact build, for rolling back |

## CI

Both pipelines run the same `ci/*.sh` scripts, so GitHub and GitLab builds
stay in sync. Each is a **single job** that builds the image and pushes it —
nothing depends on the runner's container store surviving between jobs. An
opt-in second job builds an installation ISO (see below). Every push records
its digest to an `image-digests.txt` job artifact, and the image carries
`org.opencontainers.image.*` provenance labels (revision, source, created).

### GitHub Actions (`.github/workflows/build-image.yml`)

- Runs on pushes to `main` and `ci/*`, a weekly schedule, and manual dispatch
  (`rechunk` / `build_iso` inputs; both default to `true`).
- Pushes to `ghcr.io/<owner>/<repo>` using the built-in `GITHUB_TOKEN`
  (`packages: write`). On the very first push GHCR creates the package as
  *private* — set its visibility to public if other machines should pull
  anonymously.
- The ISO is published as a GitHub release tagged `installer-iso/<image tag>`.
  Release assets must be under 2 GiB, so the ~5 GB ISO is uploaded **split
  into 2 GiB parts**; the release notes carry the reassembly commands:

  ```bash
  cat custom-silverblue-<fedora>-<tag>.iso.part* > custom-silverblue-<fedora>-<tag>.iso
  sha256sum -c custom-silverblue-<fedora>-<tag>.iso.sha256
  ```
- GitHub-hosted runners are tight on disk; both jobs start by deleting
  preinstalled toolchains. If the ISO preflight reports less than 30 GiB
  free, use a self-hosted runner (see [Runner](#runner)).

### GitLab (`.gitlab-ci.yml`)

- Pipelines run on the default branch and on schedules as a single job that
  builds the image and pushes it. The ISO job publishes to GitLab's generic
  package registry (no size problem there).
- Uses a shell executor (runner tag `tubs-kns`) and the built-in GitLab
  registry credentials — there is no secret to create (`CI_REGISTRY`,
  `CI_REGISTRY_IMAGE`, `CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD`). If the
  built-in credentials are not usable, create a project access token with the
  `write_registry` scope and point the variable references in
  `.gitlab-ci.yml` at it.
- Registry prerequisites: container registry enabled instance-wide and in
  Project → Settings → General → container registry.

### Content-based layers (optional)

Set `RECHUNK` to `true` (the default) and the job re-splits the finished
image into content-based layers with [chunkah](https://github.com/coreos/chunkah)
(`Containerfile.rechunk`) before pushing. Layers then follow the image's
content (roughly, per package) instead of the `Containerfile`'s `RUN`s, so
unchanged packages land in unchanged layers and client updates only pull what
actually changed. When enabled:

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

Set `BUILD_ISO` to `true` (the default) and a second job builds an
**Anaconda installation ISO** from the image that was just pushed. This is
the bootc `bootc-installer` recipe — the same approach Bluefin Classic uses:

1. [`Containerfile.installer`](Containerfile.installer) builds the *installer
   environment* — the image that was just published, plus Anaconda
   (`anaconda`, `anaconda-dracut`, `anaconda-install-env-deps`, lorax
   templates, …). It is built from the pushed image and is never pushed
   itself.
2. [bootc-image-builder](https://github.com/osbuild/image-builder) (osbuild,
   pinned by digest as `BIB_IMAGE`) packs that environment into an ISO and
   embeds the published image as the payload Anaconda installs. Both images
   are read from the runner's own container store, which is why the job pulls
   the image back from the registry first instead of relying on the build
   job's local tags.
3. The ISO is checksummed and published — GitLab: generic package registry
   at
   `<project URL>/-/packages/generic/installer-iso/<image tag>/custom-silverblue-<fedora version>-<image tag>.iso`
   (re-running replaces the upload for the same tag); GitHub: release
   `installer-iso/<image tag>`, split into parts (above). The osbuild
   manifest is kept as a job artifact.

**Runner requirements.** `ci/build-iso.sh` verifies these up front and fails
with a `::error::` annotation rather than an hour into the build:

| Requirement | Why |
| --- | --- |
| rootful podman (runner as root, or passwordless `sudo`) | bootc-image-builder refuses to run rootless, and buildah has to use the same store |
| `podman` next to `buildah` | bootc-image-builder is executed with it |
| ~30 GiB free next to the container store | both images, osbuild's store and the ISO live side by side |
| `osbuild-selinux` installed while SELinux is enforcing | bootc-image-builder runs privileged, so the host's policy applies inside |

One-time setup for a non-root runner: passwordless sudo for podman and
buildah (`/etc/sudoers.d/<runner>`, mode 0440):

```bash
<runner-user> ALL=(root) NOPASSWD: /usr/bin/podman, /usr/bin/buildah
```

The first run pulls `BIB_IMAGE` (~1.5 GB); later runs keep it warm.

Two things to know about the resulting ISO:

- Anaconda runs in **text mode**: bootc-image-builder hardcodes the
  `inst.text` kernel option for the `bootc-installer` image type.
- The payload is installed offline from the ISO, but the generated kickstart
  then finishes with `bootc switch --mutate-in-place --transport registry
  <payload ref>` — Anaconda pulls the exact built tag at the very end to
  point the installed system at its update source. That last step needs
  network access, and if the registry image is not pullable anonymously, also
  registry credentials; without them it reports an error after the payload is
  already installed.

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
- `/opt` is a symlink to `/var/opt` in the final image; anything a script
  installs into `/opt` needs a tmpfiles.d workaround (see
  `build_files/70-cisco-vpn.sh` for the pattern).
