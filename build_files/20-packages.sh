#!/bin/bash

set -ouex pipefail

# Codec swap: the base image ships encoder-less ffmpeg-free/libavcodec-free
# which conflict with RPM Fusion's full builds (ffmpeg, libavcodec-freeworld).
#
# This MUST stay a single dnf transaction with --allowerasing. If the codec
# packages are split across dnf calls or --allowerasing is dropped, dnf5
# resolves the conflict by picking the i686 build of libavcodec-freeworld,
# pulls in about 100 i686 packages and the solve fails. Unrelated packages
# belong in the other numbered scripts.

# Array of DNF packages to install
PACKAGES=(
	@multimedia
	ffmpeg
	libavcodec-freeworld
	intel-media-driver
	adw-gtk3-theme
	adwaita-fonts-all
	autofs
	bash-color-prompt
	cascadia-code-fonts
	cryfs
	davfs2
	ddcutil
	evtest
	fastfetch
	firewall-config
	foo2zjs
	fuse-encfs
	gcc
	gcc-c++
	git-credential-libsecret
	# gnome-tweaks
	gum
	# hplip
	ifuse
	# input-remapper
	jetbrains-mono-fonts-all
	keepassxc
	krb5-workstation
	libappindicator-gtk3
	libayatana-appindicator-gtk3
	# libimobiledevice
	# libratbag-ratbagd
	libxcrypt-compat
	lm_sensors
	make
	mesa-libGLU
	nautilus-gsconnect
	nerd-fonts
	oddjob-mkhomedir
	openssh-askpass
	powerstat
	powertop
	printer-driver-brlaser
	pulseaudio-utils
	python3-pip
	rclone
	restic
	# samba
	# samba-dcerpc
	# samba-ldb-ldap-modules
	# samba-winbind-clients
	# samba-winbind-modules
	setools-console
	sssd-nfs-idmap
	switcheroo-control
	tmux
	usbmuxd
	waypipe
	# wireguard-tools
	wl-clipboard
	xdg-terminal-exec
	xprop
	zenity
)

echo "Installing ${#PACKAGES[@]} DNF based packages..."
dnf install -y \
	--setopt=install_weak_deps=False \
	--exclude=PackageKit-gstreamer-plugin \
	--allowerasing \
	"${PACKAGES[@]}"

# Remove packages from the base image.
# Give preference to Flatpak versions of apps, but keep 
# Firefox as native app for integration with KeePassXC
REMOVE=(
	cosign
	fedora-bookmarks
	fedora-chromium-config
	fedora-chromium-config-gnome
	gnome-extensions-app
	gnome-shell-extension-background-logo
	gnome-software
	gnome-software-rpm-ostree
	gnome-terminal-nautilus
	podman-docker
	yelp
)

INSTALLED=()
for pkg in "${REMOVE[@]}"; do
	if rpm -q "${pkg}" >/dev/null 2>&1; then
		INSTALLED+=("${pkg}")
	fi
done

if [ "${#INSTALLED[@]}" -gt 0 ]; then
	dnf -y remove "${INSTALLED[@]}"
fi
