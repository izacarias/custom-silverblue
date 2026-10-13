#!/bin/bash

set -ouex pipefail

# System utilities installed from the official Fedora repositories.
#
# Distrobox comes from the Fedora RPM rather than its upstream curl installer:
# the installer targets /usr/local, which on Silverblue is a symlink to
# /var/usrlocal -- dangling at build time, so the install fails.

dnf install -y \
	vim \
	tcpdump \
	inxi \
	hwinfo \
	nmap \
	nmap-ncat \
	distrobox

# Starship
curl -sS https://starship.rs/install.sh -o /tmp/starship.sh
chmod +x /tmp/starship.sh
sh /tmp/starship.sh -f -V -a x86_64 -p unknown-linux-musl -b /usr/bin
rm -f /tmp/starship.sh

# Visual Studio Code, from Microsoft's official RPM repository.
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
dnf install -y code
