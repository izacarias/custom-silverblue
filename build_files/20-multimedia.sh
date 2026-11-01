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
#
# The `matches only excluded packages` warning from
# --exclude=PackageKit-gstreamer-plugin is expected and harmless.

dnf install -y \
	--setopt=install_weak_deps=False \
	--exclude=PackageKit-gstreamer-plugin \
	--allowerasing \
	@multimedia \
	ffmpeg \
	libavcodec-freeworld \
	intel-media-driver
