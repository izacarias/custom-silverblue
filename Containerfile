ARG BASE_IMAGE_NAME="silverblue"
ARG BASE_IMAGE_TAG="44"
ARG BASE_IMAGE_REPO="quay.io/fedora-ostree-desktops"
ARG BASE_IMAGE_REF="${BASE_IMAGE_REPO}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}"

# Allow build scripts are not copied to the final image
# instead the volume is mounted and scripts are referenced
# from there
FROM scratch AS ctx
COPY /build_files /build_files
# COPY /system_files /system_files

# Dash-to-Dock, built from the extensions/dash-to-dock git submodule. Built in
# its own stage so make/sassc/gettext never end up in the final image.
# VERSION is passed because the Makefile otherwise runs `git rev-parse HEAD`,
# which fails here; keep it in sync with the submodule's release tag.
FROM registry.fedoraproject.org/fedora:${BASE_IMAGE_TAG} AS dash-to-dock
RUN dnf -y install make sassc gettext glib2 && dnf clean all
COPY /extensions/dash-to-dock /src
RUN make -C /src install DESTDIR=/out VERSION=109

# Base Image
FROM ${BASE_IMAGE_REF} AS base

# Homebrew (tarball, setup/update units, shell integration) from ublue-os/brew.
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /usr/bin/systemctl preset brew-setup.service && \
    /usr/bin/systemctl preset brew-update.timer && \
    /usr/bin/systemctl preset brew-upgrade.timer

# Dash-to-Dock system extension; enabled by default in 60-dash-to-dock.sh.
COPY --from=dash-to-dock /out/usr /usr

# Customizations
RUN --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=bind,from=ctx,source=/build_files,target=/ctx/build_files \
    bash -euo pipefail -c ' \
	/ctx/build_files/main.sh'

# Makes `/opt` writeable by default
# Needs to be here to make the main image build strict (no /opt there)
# This is for downstream images/stuff like k0s
RUN rm -rf /opt && ln -s /var/opt /opt

# Verify final image and contents are correct.
RUN bootc container lint

CMD ["/sbin/init"]
