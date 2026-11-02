#!/bin/bash

set -ouex pipefail

# Enables the bundled GNOME extensions (Dash-to-Dock, Blur My Shell, Status
# Tray) for every user by default. They are built from the extensions/
# submodules and copied into /usr by the Containerfile. This sets the schema
# default, so users who already changed their extension list keep it, and
# anyone can still disable them.

extensions="'dash-to-dock@micxgx.gmail.com', 'blur-my-shell@aunetx', 'status-tray@keithvassallo.com'"

# Keep Fedora's own default extension enabled if the base image ships it.
if [ -d /usr/share/gnome-shell/extensions/background-logo@fedorahosted.org ]; then
	extensions="'background-logo@fedorahosted.org', ${extensions}"
fi

cat > /usr/share/glib-2.0/schemas/zz1-custom-extensions.gschema.override <<OVERRIDE
[org.gnome.shell]
enabled-extensions=[${extensions}]
OVERRIDE

# Registers libblur-effect (gnome-rounded-blur) used by Blur My Shell.
ldconfig

# Compiles the Dash-to-Dock schema together with the override. No --strict:
# Fedora's own overrides set keys that do not exist and would fail it.
glib-compile-schemas /usr/share/glib-2.0/schemas
