#!/usr/bin/env bash

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

# Adds the default web apps to the user's launcher once. Bump the version to make
# everyone add newly listed apps. If the first login is offline the entries still
# install, with a generic icon; run omadora-webapp-install again to fetch the icon.
version-script-check omadora-webapps user 1 || exit 0

set -xeuo pipefail
LIST="${OMADORA_DEFAULT_WEBAPPS:-/usr/share/omadora/default-webapps}"
while IFS='|' read -r name url; do
	[[ -z "${name}" || "${name}" == \#* ]] && continue
	/usr/bin/omadora-webapp-install "${name}" "${url}"
done <"${LIST}"
version-script-commit omadora-webapps user 1
