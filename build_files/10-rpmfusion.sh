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

# Cisco Secure Client (TU Braunschweig VPN)
# The tarball holds all Secure Client module RPMs plus the Cisco signing key
# (CiscoSystemsInc.pgp). Only the VPN module is installed: it ships the GUI,
# the `vpn` CLI and the embedded browser used for Duo/SAML logins. It conflicts
# with cisco-secure-client-vpn-cli, so don't add that one.
CISCO_TMP="$(mktemp -d)"
curl -fsSL -o "${CISCO_TMP}/cisco-secure-client.tgz" \
  "https://www.tu-braunschweig.de/index.php?eID=dumpFile&t=f&f=216248&token=861919c53edbdc799669a84fb2653d691a44f16c"
tar -xzf "${CISCO_TMP}/cisco-secure-client.tgz" -C "${CISCO_TMP}"
rpmkeys --import "${CISCO_TMP}/CiscoSystemsInc.pgp"
dnf --setopt=localpkg_gpgcheck=1 install -y "${CISCO_TMP}"/cisco-secure-client-vpn-[0-9]*.rpm
rm -rf "${CISCO_TMP}"

# The RPM installs into /opt/cisco and /opt/.cisco, but /opt is replaced by a
# symlink to /var/opt at the end of the Containerfile. Keep the files in /usr
# and link them back into /var/opt at boot via tmpfiles.d.
# secureclient/vpn is where the agent stores server-pushed profiles and its
# global prefs, so it lives in /var/lib and is seeded from /usr/share/factory.
mkdir -p /usr/lib/opt /usr/share/factory/var/lib/cisco-secureclient
mv /opt/cisco /opt/.cisco /usr/lib/opt/
mv /usr/lib/opt/cisco/secureclient/vpn /usr/share/factory/var/lib/cisco-secureclient/vpn
ln -s /var/lib/cisco-secureclient/vpn /usr/lib/opt/cisco/secureclient/vpn
cat > /usr/lib/tmpfiles.d/cisco-secure-client.conf <<'TMPFILES'
d  /var/opt                        0755 root root -
L+ /var/opt/cisco                  -    -    -    - /usr/lib/opt/cisco
L+ /var/opt/.cisco                 -    -    -    - /usr/lib/opt/.cisco
C  /var/lib/cisco-secureclient/vpn -    -    -    - /usr/share/factory/var/lib/cisco-secureclient/vpn
TMPFILES

systemctl enable vpnagentd.service