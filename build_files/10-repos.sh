#!/bin/bash

set -ouex pipefail

# Third-party repositories plus a base-image system upgrade. Everything that
# later scripts install from a non-Fedora repo is registered here.
#
# Docker CE and Tailscale ship their repo files with enabled=0 and are
# installed later with --enablerepo (40-dev-tooling.sh, 30-system-utilities.sh),
# so routine dnf use on the finished system does not hit them.

FEDORA_VERSION="$(rpm -E %fedora)"

# RPM Fusion free + nonfree, following https://rpmfusion.org/Configuration
dnf install -y distribution-gpg-keys
rpmkeys --import /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-free-fedora-${FEDORA_VERSION}
rpmkeys --import /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-nonfree-fedora-${FEDORA_VERSION}
dnf --setopt=localpkg_gpgcheck=1 install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm
dnf --setopt=localpkg_gpgcheck=1 install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm

# Microsoft Visual Studio Code (package: code, installed in 40-dev-tooling.sh)
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat > /etc/yum.repos.d/vscode.repo <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO

# Docker CE (docker-ce etc. installed in 40-dev-tooling.sh)
curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo \
	| sed 's/enabled=1/enabled=0/g' > /etc/yum.repos.d/docker-ce.repo

# Tailscale (installed in 30-system-utilities.sh)
curl -fsSL https://pkgs.tailscale.com/stable/fedora/tailscale.repo \
	| sed 's/enabled=1/enabled=0/g' > /etc/yum.repos.d/tailscale.repo

# COPR: ghostty (40-dev-tooling.sh) and nerd-fonts (30-system-utilities.sh)
curl -fsSL "https://copr.fedorainfracloud.org/coprs/scottames/ghostty/repo/fedora-${FEDORA_VERSION}/scottames-ghostty-fedora-${FEDORA_VERSION}.repo" \
	-o /etc/yum.repos.d/_copr:scottames:ghostty.repo
curl -fsSL "https://copr.fedorainfracloud.org/coprs/che/nerd-fonts/repo/fedora-${FEDORA_VERSION}/che-nerd-fonts-fedora-${FEDORA_VERSION}.repo" \
	-o /etc/yum.repos.d/_copr:che:nerd-fonts.repo

# Bring the base image up to date before anything is layered on top.
dnf upgrade --refresh -y
