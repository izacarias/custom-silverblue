#!/bin/bash

set -ouex pipefail

# System utilities installed from COPR Repositories.
#
# This should be (optimally) migrated to compile those binaries from source, 
# therefore not relying on the third-party authors.

# Distrobox
curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install -o /tmp/distrobox
chmod +x /tmp/distrobox
sh /tmp/distrobox

