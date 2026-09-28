#!/bin/bash

set -ouex pipefail

# Enable the RPM Fusion free + nonfree repositories, following
# https://rpmfusion.org/Configuration
#
# rpm-ostree install is used rather than dnf so the release RPMs are layered
# the same way they would be on a booted system. This works fine inside the
# build container: it exits 0 and leaves the repos enabled for later dnf calls.

FEDORA_VERSION="$(rpm -E %fedora)"

rpm-ostree install -y \
	"https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
	"https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
