ARG BASE_IMAGE_NAME="fedora-silverblue"
ARG BASE_IMAGE_TAG="45"
ARG BASE_IMAGE_REPO="quay.io/fedora"
ARG BASE_IMAGE_REF="${BASE_IMAGE_REPO}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}"

# Scripts are mounted temporarily to avoid copying them to the image
FROM scratch AS ctx
COPY /build_files /build_files

# Use to copy system and configuration files to the final image.
# Not used, but left here for reference.
# COPY /system_files /system_files

# Dash-to-Dock, built from the extensions/dash-to-dock git submodule. Built in
# its own stage so make/sassc/gettext never end up in the final image.
# VERSION is passed because the Makefile otherwise runs `git rev-parse HEAD`,
# which fails here; keep it in sync with the submodule's release tag.
FROM ${BASE_IMAGE_REF} AS dash-to-dock
RUN dnf -y install make sassc gettext glib2 && dnf clean all
COPY /extensions/dash-to-dock /src
RUN make -C /src install DESTDIR=/out VERSION=109

# gnome-rounded-blur (extensions/gnome-rounded-blur submodule): native rounded
# corners for Blur My Shell. Mirrors upstream's scripts/rounded_blur_build.sh,
# but built against the base image so mutter-devel matches the shipped mutter.
FROM ${BASE_IMAGE_REF} AS rounded-blur
RUN dnf -y install gcc meson mutter-devel glib2-devel gobject-introspection-devel && dnf clean all
COPY /extensions/gnome-rounded-blur /src
RUN meson setup /build /src --prefix=/usr && \
    meson compile -C /build && \
    meson install -C /build --destdir /out

# Blur My Shell (extensions/blur-my-shell submodule), packed with upstream's
# `make build` (needs gnome-extensions, hence the base image) and unpacked as a
# system extension.
FROM ${BASE_IMAGE_REF} AS blur-my-shell
RUN dnf -y install make gettext unzip && dnf clean all
COPY /extensions/blur-my-shell /src
RUN make -C /src build && \
    mkdir -p /out/usr/share/gnome-shell/extensions/blur-my-shell@aunetx && \
    unzip /src/build/blur-my-shell@aunetx.shell-extension.zip \
          -d /out/usr/share/gnome-shell/extensions/blur-my-shell@aunetx && \
    glib-compile-schemas /out/usr/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas

# Status Tray (extensions/status-tray submodule): AppIndicator/StatusNotifierItem
# system tray. Pure JS, so the only build step is compiling its GSettings schema.
FROM ${BASE_IMAGE_REF} AS status-tray
COPY /extensions/status-tray/src /src
RUN mkdir -p /out/usr/share/gnome-shell/extensions/status-tray@keithvassallo.com && \
    cp -a /src/. /out/usr/share/gnome-shell/extensions/status-tray@keithvassallo.com/ && \
    glib-compile-schemas /out/usr/share/gnome-shell/extensions/status-tray@keithvassallo.com/schemas

# Gradia Capture (extensions/gradia-capture submodule): screenshot
# annotations. Pure JS, so the only build step is compiling its GSettings
# schema. Unlike status-tray, the install layout also needs icons/ and
# schemas/ — both live outside src/ upstream, and src/tools.js loads icons
# from an icons/ dir next to extension.js (the same layout upstream's
# `gnome-extensions pack` build.sh produces). The UUID says "gradia-integration"
# although the repo is "gradia-capture"; it must match metadata.json, so keep
# it verbatim.
FROM ${BASE_IMAGE_REF} AS gradia-capture
COPY /extensions/gradia-capture/src /src
COPY /extensions/gradia-capture/icons /icons
COPY /extensions/gradia-capture/schemas /schemas
RUN mkdir -p /out/usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io && \
    cp -a /src/. /out/usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io/ && \
    cp -a /icons /out/usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io/icons && \
    cp -a /schemas /out/usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io/schemas && \
    glib-compile-schemas /out/usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io/schemas

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

# Dash-to-Dock system extension; enabled by default in 60-gnome-extensions.sh.
COPY --from=dash-to-dock /out/usr /usr

# Blur My Shell + gnome-rounded-blur runtime files (no headers/gir/pkg-config);
# enabled by default in 60-gnome-extensions.sh.
COPY --from=rounded-blur /out/usr/lib64/libblur-effect-1.0.so* /usr/lib64/
COPY --from=rounded-blur /out/usr/lib64/girepository-1.0/Blur-1.0.typelib /usr/lib64/girepository-1.0/
COPY --from=blur-my-shell /out/usr /usr

# Status Tray system extension; enabled by default in 60-gnome-extensions.sh.
COPY --from=status-tray /out/usr /usr

# Gradia Capture system extension; enabled by default in 60-gnome-extensions.sh.
COPY --from=gradia-capture /out/usr /usr

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
