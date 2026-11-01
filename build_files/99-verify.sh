#!/bin/bash

set -ouex pipefail

# Build-time sanity checks (Bluefin runs a similar test stage). Catches a
# package silently missing from a big transaction before the image is pushed;
# `bootc container lint` at the end of the Containerfile covers image layout.

PRESENT=(
	keepassxc
	firefox
	ffmpeg
	libavcodec-freeworld
	intel-media-driver
	code
	ghostty
	distrobox
	docker-ce
	docker-compose-plugin
	podman-compose
	libvirt
	virt-manager
	virt-viewer
	qemu-system-x86-core
	edk2-ovmf
	tailscale
)

for pkg in "${PRESENT[@]}"; do
	if ! rpm -q "${pkg}" >/dev/null 2>&1; then
		echo "::error::expected package ${pkg} is not installed"
		exit 1
	fi
done

# 35-trim.sh must have removed these
ABSENT=(
	gnome-software
	yelp
	podman-docker
	cosign
)

for pkg in "${ABSENT[@]}"; do
	if rpm -q "${pkg}" >/dev/null 2>&1; then
		echo "::error::package ${pkg} should not be installed"
		exit 1
	fi
done

# starship is a plain binary, not an RPM
test -x /usr/bin/starship

# Built by the Containerfile extension stages
test -d /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com
test -d /usr/share/gnome-shell/extensions/blur-my-shell@aunetx

echo "All checks passed"
