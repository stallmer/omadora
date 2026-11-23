#!/usr/bin/env bash

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

# Copies Omadora's default user files (the Noctalia theme placeholders and the
# Noctalia defaults include) into the home directory once. It needs no network
# and never overwrites a file the user already has. Bump the version to make
# every user pick up newly added files.
version-script-check omadora-skel user 1 || exit 0

set -xeuo pipefail
/usr/bin/omadora-setup --skel
version-script-commit omadora-skel user 1
