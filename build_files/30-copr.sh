#!/bin/bash

set -ouex pipefail

# System utilities installed from COPR Repositories.
#
# This should be (optimally) migrated to compile those binaries from source, 
# therefore not relying on the third-party authors.

# Ghostty

FEDORA_VERSION="$(rpm -E %fedora)"
sudo curl -sL "https://copr.fedorainfracloud.org/coprs/scottames/ghostty/repo/fedora-${FEDORA_VERSION}/scottames-ghostty-fedora-${FEDORA_VERSION}.repo" \
  | sudo tee /etc/yum.repos.d/_copr:scottames:ghostty.repo
  
dnf check-update
dnf install ghostty


