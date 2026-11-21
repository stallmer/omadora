#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# JetBrains Mono Nerd Font
###############################################################################
# Fedora ships JetBrains Mono without the Nerd Font icons that starship, eza and
# similar tools draw, so this font comes from the Nerd Fonts release. It is
# pinned by version and sha256, so a changed or tampered download fails the
# build. Renovate does not manage this pin; bump VERSION and SHA256 together
# (the checksum is in the release's SHA-256.txt).
#
# Only the standard "JetBrainsMono Nerd Font" files are installed (16 weights),
# not the Mono, Propo and NL variants, to keep the image small. fc-cache is not
# run: 90-cleanup.sh clears /var/cache, and fontconfig rebuilds it at runtime.
###############################################################################

VERSION="v3.5.1"
SHA256="04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf"
URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${VERSION}/JetBrainsMono.tar.xz"

echo "::group:: Install JetBrains Mono Nerd Font"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

curl --fail --retry 3 --silent --show-error --location \
	--output "${tmp}/font.tar.xz" "${URL}"
echo "${SHA256}  ${tmp}/font.tar.xz" | sha256sum --check --strict

tar -xJf "${tmp}/font.tar.xz" -C "${tmp}" --wildcards 'JetBrainsMonoNerdFont-*.ttf' OFL.txt
install -d -m0755 /usr/share/fonts/jetbrains-mono-nerd
install -m0644 "${tmp}"/JetBrainsMonoNerdFont-*.ttf "${tmp}/OFL.txt" \
	/usr/share/fonts/jetbrains-mono-nerd/

echo "::endgroup::"
