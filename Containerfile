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
