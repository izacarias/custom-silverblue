#!/bin/bash

set -ouex pipefail

echo "::begin-group:: ===$(basename "$0")==="

# Install multimidia codecs on Silverblue
sudo dnf group install -y multimedia

echo "::end-group:: ===$(basename "$0")==="
