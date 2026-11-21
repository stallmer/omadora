#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Desktop base: Niri compositor, Noctalia shell, SDDM
###############################################################################
# Phase 2 of the Omadora build plan. base-main ships no desktop, so this
# script installs one. Everything comes from the Fedora 44 repositories; no COPR
# is needed. Verified against the base image with a dnf dry run.
#
#   niri, noctalia              compositor and shell (bar, launcher,
#                               notifications, lock screen, wallpaper, OSD)
#   sddm, sddm-wayland-generic  display manager; the Wayland greeter backend
#                               avoids pulling in Xorg
#   xdg-desktop-portal-gnome    Niri's screencast portal (-gtk for file pickers)
#   gnome-keyring               Secret Service provider Noctalia wants
#   swayidle, gammastep         idle handling and night light, wired up later
#   xwayland-satellite          X11 app support for Niri
#   power-profiles-daemon       optional Noctalia power-profile switching
#   alacritty                   terminal (ghostty is not in the repositories)
###############################################################################

echo "::group:: Install the Niri desktop"

dnf5 install -y \
	niri \
	noctalia \
	sddm \
	sddm-wayland-generic \
	xdg-desktop-portal-gnome \
	xdg-desktop-portal-gtk \
	gnome-keyring \
	swayidle \
	gammastep \
	xwayland-satellite \
	power-profiles-daemon \
	alacritty

echo "::endgroup::"

echo "::group:: Ship the system Niri config"

# niri reads ~/.config/niri/config.kdl first and falls back to /etc/niri/config.kdl.
# Start from the package's own default and swap its Waybar autostart for Noctalia.
install -Dm0644 /usr/share/doc/niri/default-config.kdl /etc/niri/config.kdl
if ! grep -qx 'spawn-at-startup "waybar"' /etc/niri/config.kdl; then
	echo "::error::niri's default config no longer starts waybar; update this script" >&2
	exit 1
fi
sed -i 's|^spawn-at-startup "waybar"$|spawn-at-startup "noctalia" "--daemon"|' /etc/niri/config.kdl

echo "::endgroup::"

echo "::group:: Enable the display manager"

systemctl enable sddm.service

echo "::endgroup::"
