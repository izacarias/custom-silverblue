#!/bin/bash

set -ouex pipefail

# Enables Dash-to-Dock for every user by default. The extension itself is
# built from the extensions/dash-to-dock submodule and copied into /usr by the
# Containerfile. This sets the schema default, so users who already changed
# their extension list keep it, and anyone can still disable the dock.

extensions="'dash-to-dock@micxgx.gmail.com'"

# Keep Fedora's own default extension enabled if the base image ships it.
if [ -d /usr/share/gnome-shell/extensions/background-logo@fedorahosted.org ]; then
	extensions="'background-logo@fedorahosted.org', ${extensions}"
fi

cat > /usr/share/glib-2.0/schemas/zz1-custom-extensions.gschema.override <<OVERRIDE
[org.gnome.shell]
enabled-extensions=[${extensions}]
OVERRIDE

# Compiles the Dash-to-Dock schema together with the override. No --strict:
# Fedora's own overrides set keys that do not exist and would fail it.
glib-compile-schemas /usr/share/glib-2.0/schemas
