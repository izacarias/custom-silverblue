#!/bin/bash

set -ouex pipefail

# System utilities, modelled on Bluefin's base package set (ublue-os/bluefin
# build_files/base/04-packages.sh) but keeping Fedora's own application set:
# Firefox and KeePassXC are installed natively (RPM) so KeePassXC's browser
# integration works over native messaging.

dnf install -y \
	adcli \
	adw-gtk3-theme \
	adwaita-fonts-all \
	autofs \
	bash-color-prompt \
	borgbackup \
	cascadia-code-fonts \
	cryfs \
	davfs2 \
	ddcutil \
	evtest \
	fastfetch \
	firewall-config \
	fish \
	foo2zjs \
	fuse-encfs \
	gcc \
	gcc-c++ \
	git-credential-libsecret \
	glow \
	gnome-tweaks \
	gum \
	hplip \
	ifuse \
	input-remapper \
	jetbrains-mono-fonts-all \
	keepassxc \
	krb5-workstation \
	libappindicator-gtk3 \
	libayatana-appindicator-gtk3 \
	libimobiledevice \
	libratbag-ratbagd \
	libxcrypt-compat \
	lm_sensors \
	make \
	mesa-libGLU \
	nautilus-gsconnect \
	nerd-fonts \
	oddjob-mkhomedir \
	openssh-askpass \
	powerstat \
	powertop \
	printer-driver-brlaser \
	pulseaudio-utils \
	python3-pip \
	rclone \
	restic \
	samba \
	samba-dcerpc \
	samba-ldb-ldap-modules \
	samba-winbind-clients \
	samba-winbind-modules \
	setools-console \
	sssd-nfs-idmap \
	switcheroo-control \
	tmux \
	usbmuxd \
	waypipe \
	wireguard-tools \
	wl-clipboard \
	xdg-terminal-exec \
	xprop \
	zenity \
	zsh

# Tailscale (repo added in 10-repos.sh, kept disabled)
dnf install -y --enablerepo=tailscale-stable tailscale
