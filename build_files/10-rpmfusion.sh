#!/bin/bash

set -ouex pipefail

# Enable the RPM Fusion free + nonfree repositories, following
# https://rpmfusion.org/Configuration
#
# rpm-ostree install is used rather than dnf so the release RPMs are layered
# the same way they would be on a booted system. This works fine inside the
# build container: it exits 0 and leaves the repos enabled for later dnf calls.

FEDORA_VERSION="$(rpm -E %fedora)"

dnf install -y distribution-gpg-keys
rpmkeys --import /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-free-fedora-${FEDORA_VERSION}
rpmkeys --import /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-nonfree-fedora-${FEDORA_VERSION}
dnf --setopt=localpkg_gpgcheck=1 install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm 
dnf --setopt=localpkg_gpgcheck=1 install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Other RPM repositories

# Microsoft Visual Studio Code
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

# Perfom a system update to ensure all packages are up to date
dnf upgrade --refresh -y

# Install multimedia codecs and Intel video acceleration packages
# including packages from RPM Fusion repositories
dnf install -y \
	--setopt=install_weak_deps=False \
	--exclude=PackageKit-gstreamer-plugin \
	--allowerasing \
	@multimedia \
	ffmpeg \
	libavcodec-freeworld \
	intel-media-driver \
	vim \
	tcpdump \
	inxi \
	hwinfo \
	nmap \
	nmap-ncat \
	distrobox \
    code

# Starship for nice prompt
curl -sS https://starship.rs/install.sh -o /tmp/starship.sh
chmod +x /tmp/starship.sh
sh /tmp/starship.sh -f -V -a x86_64 -p unknown-linux-musl -b /usr/bin
rm -f /tmp/starship.sh

# COPR Repositories

# Ghostty
curl -sL "https://copr.fedorainfracloud.org/coprs/scottames/ghostty/repo/fedora-${FEDORA_VERSION}/scottames-ghostty-fedora-${FEDORA_VERSION}.repo" \
  | tee /etc/yum.repos.d/_copr:scottames:ghostty.repo
dnf install -y ghostty