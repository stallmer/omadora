#!/usr/bin/env bash

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

# Runs at each graphical login until it succeeds, so an offline first login
# retries next time. Bump the version to make every user re-apply once.
version-script-check omadora-dotfiles user 1 || exit 0

set -xeuo pipefail
/usr/bin/omadora-setup
version-script-commit omadora-dotfiles user 1
