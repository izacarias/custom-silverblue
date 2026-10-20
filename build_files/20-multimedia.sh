#!/bin/bash

set -ouex pipefail

# Multimedia codecs + Intel video acceleration.
#
# IMPORTANT: this must stay a *single* transaction with --allowerasing.
#
# Splitting it makes dnf5 fail in a sneaky way. The base image ships
# libavcodec-free/ffmpeg-free, and RPM Fusion's replacements conflict with
# them. Without --allowerasing, dnf resolves the group by grabbing the *i686*
# build of libavcodec-freeworld instead of erasing the x86_64 one -- which is
# useless on x86_64 and drags in ~100 i686 dependencies before the solve dies.
#
# --exclude=PackageKit-gstreamer-plugin prints a harmless
# "matches only excluded packages" warning and still exits 0; PackageKit's
# GStreamer plugin is left out on purpose (per the Fedora wiki recipe).

dnf upgrade --refresh && \
dnf install -y \
	--setopt=install_weak_deps=False \
	--exclude=PackageKit-gstreamer-plugin \
	--allowerasing \
	@multimedia \
	ffmpeg \
	libavcodec-freeworld \
	intel-media-driver
