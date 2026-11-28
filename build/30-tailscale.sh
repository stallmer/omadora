#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Tailscale from the vendor RPM repository
###############################################################################
# Third-party repository pattern: add the vendor's repository, install from it,
# then take the repository back out. The image ships no live third-party source
# and no repository file left enabled to rot.
#
# Fedora also packages tailscale, but lags upstream by several releases. The
# vendor repository is used to track current upstream builds.
###############################################################################

echo "::group:: Install Tailscale"

# Let dnf5 fetch the vendor's own .repo file instead of hand-writing one, so
# baseurl and gpgkey stay the vendor's responsibility and cannot drift.
dnf5 config-manager addrepo --overwrite \
	--from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 install -y tailscale

# Remove the repository file. A third-party repository is a build-time source
# only; 90-cleanup.sh also disables tailscale.repo as a backstop, and now
# disables every other repository the build added by ownership, not just by
# name.
rm -f /etc/yum.repos.d/tailscale.repo

echo "::endgroup::"

echo "::group:: Enable the Tailscale daemon"

# tailscaled runs the tailnet. Joining one is a first-boot action for the person
# at the machine, so the image only enables the unit: it never runs
# `tailscale up` and never embeds an auth key.
systemctl enable tailscaled.service

echo "::endgroup::"
