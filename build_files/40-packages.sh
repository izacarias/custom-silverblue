#!/bin/bash

set -ouex pipefail

# System utilities installed from the official Fedora repositories.
#
# Distrobox comes from the Fedora RPM rather than its upstream curl installer:
# the installer targets /usr/local, which on Silverblue is a symlink to
# /var/usrlocal -- dangling at build time, so the install fails.

dnf install -y \
	vim \
	distrobox
