#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Steam
###############################################################################
# Steam comes from the negativo17 "fedora-multimedia" repository, which
# ublue-os/base-main enables while the image builds. 90-cleanup.sh disables
# that repository again, so the shipped image keeps no live third-party source.
# If base-main ever stops enabling it, this install fails loudly.
#
# steam-devices ships the udev rules that let Steam see game controllers.
#
# This is its own phase, ahead of the desktop phase, so the large Steam layer
# is not invalidated whenever the desktop script changes. That keeps image
# updates smaller.
###############################################################################

echo "::group:: Install Steam"

dnf5 install -y \
	steam \
	steam-devices

echo "::endgroup::"
