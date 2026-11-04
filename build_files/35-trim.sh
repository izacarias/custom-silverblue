#!/bin/bash

set -ouex pipefail

# Bluefin's "apps live in Flatpak" trim, minus Firefox (kept native together
# with keepassxc so browser integration uses native messaging). Only packages
# that are actually installed are removed.


