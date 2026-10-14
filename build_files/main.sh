#!/bin/bash

set -ouex pipefail

# Runs every numbered customisation script in build_files/ in lexical order.
# Drop a new NN-name.sh in here to extend the image; no Containerfile change
# needed, because the whole directory is bind-mounted from the ctx stage.

echo "::begin-group:: ===$(basename "$0")==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for script in "$SCRIPT_DIR"/[0-9]*.sh; do
	[ -e "$script" ] || continue
	echo "::begin-group:: ===$(basename "$script")==="
	bash "$script"
	echo "::end-group:: ===$(basename "$script")==="
done

# Enabling systemd services
# Podman
systemctl enable podman.socket

# Disabling services that are not used in my day-by-day usage
# Passim (firmware update file sharing daemon)
systemctl disable passim.service


# Build residue from dnf/rpm-ostree would otherwise be baked into the image and
# trip `bootc container lint`. Always clean up after the scripts, whatever
# they installed.
rm -rf /run/dnf /run/rpm-ostree
rm -rf /var/cache/libdnf5 /var/cache/rpm-ostree /var/cache/ldconfig
rm -rf /var/lib/dnf
rm -f /var/log/dnf5.log

# The base image ships /var/tmp only, so drop any directory we just emptied
# back to that state. rmdir keeps any content a future script added.
rmdir /var/cache /var/lib /var/log 2>/dev/null || true

echo "::end-group:: ===$(basename "$0")==="
