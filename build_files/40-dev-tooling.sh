#!/bin/bash

set -ouex pipefail

# Developer tooling, modelled on Bluefin DX (ublue-os/bluefin
# build_files/dx/00-dx.sh). The VM stack lives in 50-virtualization.sh.

# Docker CE stack (repo added in 10-repos.sh, kept disabled)
dnf install -y --enablerepo=docker-ce-stable \
	containerd.io \
	docker-buildx-plugin \
	docker-ce \
	docker-ce-cli \
	docker-compose-plugin

# Fedora packages
dnf install -y \
	android-tools \
	bcc \
	bpftop \
	bpftrace \
	distrobox \
	flatpak-builder \
	genisoimage \
	git-subtree \
	git-svn \
	hwinfo \
	inxi \
	just \
	nicstat \
	nmap \
	nmap-ncat \
	numactl \
	p7zip \
	p7zip-plugins \
	podman-compose \
	podman-machine \
	podman-tui \
	tcpdump \
	tiptop \
	trace-cmd \
	udica \
	util-linux-script \
	vim \
	wtype \
	ydotool

# VS Code (Microsoft repo) and ghostty (COPR), both added in 10-repos.sh
dnf install -y code ghostty

# Starship for a nice prompt
curl -sS https://starship.rs/install.sh -o /tmp/starship.sh
chmod +x /tmp/starship.sh
sh /tmp/starship.sh -f -V -a x86_64 -p unknown-linux-musl -b /usr/bin
rm -f /tmp/starship.sh
