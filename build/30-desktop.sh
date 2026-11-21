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
#   xwayland-satellite          X11 app support for Niri
#
# Noctalia handles idle (lock, screen off, suspend) and night light itself, so
# swayidle and gammastep are not installed. Its idle timeouts are in
# custom/files/etc/xdg/noctalia/10-omadora.toml.
#
#   power-profiles-daemon       optional Noctalia power-profile switching
#   alacritty                   terminal (ghostty is not in the repositories)
#   chezmoi                     applies the Omadora dotfiles on first login
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
	xwayland-satellite \
	power-profiles-daemon \
	alacritty \
	chezmoi

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

# The stock binds call fuzzel, swaylock, playerctl and brightnessctl, none of
# which is installed, and wpctl, which would bypass Noctalia's volume OSD. Point
# them at Noctalia's own IPC. rebind replaces the first argument with the second
# and stops the build if Niri's default config no longer contains it.
rebind() {
	local old="$1" new="$2"
	if ! grep -qF -- "${old}" /etc/niri/config.kdl; then
		echo "::error::niri's default config no longer contains: ${old}" >&2
		exit 1
	fi
	sed -i "s|${old}|${new}|" /etc/niri/config.kdl
}

# Launcher and lock screen.
rebind 'hotkey-overlay-title="Run an Application: fuzzel" { spawn "fuzzel"; }' \
	'hotkey-overlay-title="Run an Application: Noctalia launcher" { spawn "noctalia" "msg" "panel-toggle" "launcher"; }'
rebind 'hotkey-overlay-title="Lock the Screen: swaylock" { spawn "swaylock"; }' \
	'hotkey-overlay-title="Lock the Screen: Noctalia" { spawn "noctalia" "msg" "session" "lock"; }'

# Volume and microphone, so Noctalia shows its on-screen display.
rebind '{ spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0"; }' '{ spawn "noctalia" "msg" "volume-up"; }'
rebind '{ spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-"; }' '{ spawn "noctalia" "msg" "volume-down"; }'
rebind '{ spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }' '{ spawn "noctalia" "msg" "volume-mute"; }'
rebind '{ spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"; }' '{ spawn "noctalia" "msg" "mic-mute"; }'

# Media playback goes to the active MPRIS player.
rebind '{ spawn-sh "playerctl play-pause"; }' '{ spawn "noctalia" "msg" "media" "toggle"; }'
rebind '{ spawn-sh "playerctl stop"; }' '{ spawn "noctalia" "msg" "media" "stop"; }'
rebind '{ spawn-sh "playerctl previous"; }' '{ spawn "noctalia" "msg" "media" "previous"; }'
rebind '{ spawn-sh "playerctl next"; }' '{ spawn "noctalia" "msg" "media" "next"; }'

# Screen brightness.
rebind '{ spawn "brightnessctl" "--class=backlight" "set" "+10%"; }' '{ spawn "noctalia" "msg" "brightness-up"; }'
rebind '{ spawn "brightnessctl" "--class=backlight" "set" "10%-"; }' '{ spawn "noctalia" "msg" "brightness-down"; }'

echo "::endgroup::"

echo "::group:: Enable the display manager"

systemctl enable sddm.service

echo "::endgroup::"
