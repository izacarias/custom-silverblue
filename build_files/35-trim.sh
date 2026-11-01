#!/bin/bash

set -ouex pipefail

# Bluefin's "apps live in Flatpak" trim, minus Firefox (kept native together
# with keepassxc so browser integration uses native messaging). Only packages
# that are actually installed are removed.

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
