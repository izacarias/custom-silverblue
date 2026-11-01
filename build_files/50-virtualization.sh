#!/bin/bash

set -ouex pipefail

# Virtual machines: QEMU/KVM via libvirt + virt-manager, modelled on the VM
# half of Bluefin DX (no Cockpit, no Incus). Containers are covered by
# 40-dev-tooling.sh.

dnf install -y \
	edk2-ovmf \
	libvirt \
	libvirt-daemon-config-network \
	libvirt-nss \
	qemu \
	qemu-char-spice \
	qemu-device-display-virtio-gpu \
	qemu-device-display-virtio-vga \
	qemu-device-usb-redirect \
	qemu-img \
	qemu-system-x86-core \
	qemu-user-binfmt \
	qemu-user-static \
	virt-manager \
	virt-viewer \
	virt-v2v

# iptable_nat at boot for docker-in-docker / devcontainers.
# See https://github.com/ublue-os/bluefin/issues/2365
mkdir -p /etc/modules-load.d
cat > /etc/modules-load.d/ip_tables.conf <<'EOF'
iptable_nat
EOF

# A newer selinux-policy from the layered packages overwrites rpm-ostree's
# subs_dist fix; put it back (same fix Bluefin DX applies).
sed -i 's|^/var/home[[:space:]]\+/home$|/home /var/home|' \
	/etc/selinux/targeted/contexts/files/file_contexts.subs_dist

# Autostart libvirt's default NAT network. `virsh net-autostart` cannot run at
# build time (no libvirt daemon); the symlink is what it would create.
if [ -f /etc/libvirt/qemu/networks/default.xml ]; then
	mkdir -p /etc/libvirt/qemu/networks/autostart
	ln -sf ../../default.xml /etc/libvirt/qemu/networks/autostart/default.xml
fi

# Group membership has to happen at boot: the image has no regular users at
# build time. Equivalent of Bluefin's bluefin-dx-groups.service.
cat > /usr/libexec/dev-groups <<'SCRIPT'
#!/bin/bash
# Adds every local user (home under /var/home) to the docker and libvirt
# groups so docker and virt-manager work without sudo. Runs once per boot;
# harmless to re-run (usermod -aG is idempotent).
set -eu

for home in /var/home/*; do
	[ -d "${home}" ] || continue
	user="$(stat -c %U "${home}")"
	if [ "${user}" = "root" ]; then
		continue
	fi
	for group in docker libvirt; do
		if getent group "${group}" >/dev/null; then
			usermod -aG "${group}" "${user}"
		fi
	done
done
SCRIPT
chmod +x /usr/libexec/dev-groups

cat > /usr/lib/systemd/system/dev-groups.service <<'UNIT'
[Unit]
Description=Add local users to docker and libvirt groups
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/dev-groups
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable dev-groups.service
systemctl enable docker.socket
systemctl enable podman.socket
systemctl enable virtqemud.socket
systemctl enable virtnetworkd.socket
