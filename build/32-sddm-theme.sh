#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# SDDM login screen theme (Noctalia look)
###############################################################################
# Installs the Qt6 theme from github.com/ClementFombonne/sddm-noctalia-theme, a
# port of the Noctalia lock screen with the same ten palettes (including
# Tokyo-Night). The upstream repository is archived, so the pin is a deliberate
# freeze: it is by commit and sha256 (of the GitHub archive tarball for that
# commit), Renovate does not manage it, and COMMIT and SHA256 change together.
#
# Only the theme files are installed. The upstream install.sh, uninstall.sh and
# the nix/ files are left out: they write to /usr/share at run time, which is
# read-only on a bootc system.
#
# The theme reads its colours from Commons/Settings.conf. That path is under
# /usr, which cannot be edited on the running system, so it becomes a symlink
# to /etc/omadora/sddm-theme.conf (shipped by custom/files, and rewritten by
# omadora-theme-set through the omadora-sddm-theme helper). The SDDM drop-in
# that selects the theme is /etc/sddm.conf.d/10-omadora-theme.conf. If the theme
# fails to load, SDDM falls back to its embedded theme.
###############################################################################

COMMIT="92bf8e6ff35be19b50b60a38e0f3d6e38e1c66e1"
SHA256="6d5c65560758c6be9db9f278909e8fb0891750547972969103a0ce702b2261af"
URL="https://github.com/ClementFombonne/sddm-noctalia-theme/archive/${COMMIT}.tar.gz"
THEME_DIR="/usr/share/sddm/themes/noctalia-shell"
CONF="/etc/omadora/sddm-theme.conf"

echo "::group:: Install the SDDM theme"

if [[ ! -f "${CONF}" ]]; then
	echo "::error::${CONF} is missing; custom/files should have shipped it" >&2
	exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

curl --fail --retry 3 --silent --show-error --location \
	--output "${tmp}/theme.tar.gz" "${URL}"
echo "${SHA256}  ${tmp}/theme.tar.gz" | sha256sum --check --strict

tar -xzf "${tmp}/theme.tar.gz" -C "${tmp}"
src="${tmp}/sddm-noctalia-theme-${COMMIT}"

if ! grep -qx 'QtVersion=6' "${src}/metadata.desktop"; then
	echo "::error::the pinned theme no longer declares QtVersion=6" >&2
	exit 1
fi

install -d -m0755 "${THEME_DIR}"
cp -r "${src}/Assets" "${src}/Commons" "${src}/Helpers" "${src}/Widgets" \
	"${src}/Main.qml" "${src}/metadata.desktop" "${src}/qmldir" \
	"${src}/LICENSE" "${src}/README.md" "${THEME_DIR}/"
chmod -R u=rwX,go=rX "${THEME_DIR}"
chown -R root:root "${THEME_DIR}"

ln -sf "${CONF}" "${THEME_DIR}/Commons/Settings.conf"

echo "::endgroup::"
