#!/usr/bin/env bats
# Unit tests for the login screen theme: the privileged helper, the shipped
# defaults, the polkit policy and the build script's pin.
#
# Run with: bats tests/template/omadora-sddm-theme_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
ROOT="${SCRIPT_DIR}/../.."
HELPER="${ROOT}/custom/files/usr/libexec/omadora-sddm-theme"
DEFAULT_CONF="${ROOT}/custom/files/etc/omadora/sddm-theme.conf"
POLICY="${ROOT}/custom/files/usr/share/polkit-1/actions/org.omadora.sddm-theme.policy"
DROPIN="${ROOT}/custom/files/etc/sddm.conf.d/10-omadora-theme.conf"
BUILD="${ROOT}/build/32-sddm-theme.sh"
THEME_SET="${ROOT}/custom/files/usr/bin/omadora-theme-set"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/sddm-theme.${BATS_TEST_NUMBER:-0}.$$"
	mkdir -p "${TEST_ROOT}"
	export OMADORA_SDDM_CONF="${TEST_ROOT}/sddm-theme.conf"
	cp "${DEFAULT_CONF}" "${OMADORA_SDDM_CONF}"
}

@test "helper: scheme rewrites colorScheme and leaves every other line alone" {
	run "${HELPER}" scheme Gruvbox
	[ "$status" -eq 0 ]
	grep -qx 'colorScheme="Gruvbox"' "${OMADORA_SDDM_CONF}"
	diff <(grep -v '^colorScheme=' "${DEFAULT_CONF}") <(grep -v '^colorScheme=' "${OMADORA_SDDM_CONF}")
}

@test "helper: mode rewrites darkMode" {
	run "${HELPER}" mode light
	[ "$status" -eq 0 ]
	grep -qx 'darkMode=false' "${OMADORA_SDDM_CONF}"
	run "${HELPER}" mode dark
	[ "$status" -eq 0 ]
	grep -qx 'darkMode=true' "${OMADORA_SDDM_CONF}"
}

@test "helper: a missing key is appended" {
	grep -v '^darkMode=' "${DEFAULT_CONF}" >"${OMADORA_SDDM_CONF}"
	run "${HELPER}" mode light
	[ "$status" -eq 0 ]
	[ "$(grep -c '^darkMode=' "${OMADORA_SDDM_CONF}")" -eq 1 ]
	grep -qx 'darkMode=false' "${OMADORA_SDDM_CONF}"
}

@test "helper: an unknown scheme or mode exits 2 and changes nothing" {
	run "${HELPER}" scheme 'Tokyo-Night"; evil=1'
	[ "$status" -eq 2 ]
	run "${HELPER}" scheme bogus
	[ "$status" -eq 2 ]
	run "${HELPER}" mode auto
	[ "$status" -eq 2 ]
	run "${HELPER}" bogus x
	[ "$status" -eq 2 ]
	run "${HELPER}"
	[ "$status" -eq 2 ]
	cmp "${DEFAULT_CONF}" "${OMADORA_SDDM_CONF}"
}

@test "helper: a missing config file is an error" {
	rm "${OMADORA_SDDM_CONF}"
	run "${HELPER}" scheme Nord
	[ "$status" -eq 1 ]
	[[ "$output" == *"not found"* ]]
}

@test "helper: the file stays world-readable and no temp files are left behind" {
	run "${HELPER}" scheme Dracula
	[ "$status" -eq 0 ]
	[ "$(stat -c %a "${OMADORA_SDDM_CONF}")" = "644" ]
	[ "$(find "${TEST_ROOT}" -name 'sddm-theme.conf.*' | wc -l)" -eq 0 ]
}

@test "helper: every login scheme omadora-theme-set can send is accepted" {
	for theme in Ayu Catppuccin Dracula Eldritch Gruvbox Kanagawa Nord Tokyo-Night Rosepine Noctalia-default; do
		run "${HELPER}" scheme "${theme}"
		[ "$status" -eq 0 ]
	done
}

@test "defaults: the shipped config starts on Tokyo-Night in dark mode" {
	grep -qx 'colorScheme="Tokyo-Night"' "${DEFAULT_CONF}"
	grep -qx 'darkMode=true' "${DEFAULT_CONF}"
}

@test "defaults: the SDDM drop-in selects the installed theme directory" {
	grep -qx 'Current=noctalia-shell' "${DROPIN}"
	grep -q 'THEME_DIR="/usr/share/sddm/themes/noctalia-shell"' "${BUILD}"
}

@test "polkit: the action points at the helper and only an active session skips the prompt" {
	grep -q '<annotate key="org.freedesktop.policykit.exec.path">/usr/libexec/omadora-sddm-theme</annotate>' "${POLICY}"
	grep -q '<allow_active>yes</allow_active>' "${POLICY}"
	grep -q '<allow_any>auth_admin</allow_any>' "${POLICY}"
	grep -q 'pkexec /usr/libexec/omadora-sddm-theme' "${THEME_SET}"
}

@test "build: the theme is pinned by a full commit and a sha256, and the symlink targets the shipped config" {
	grep -Eq '^COMMIT="[0-9a-f]{40}"$' "${BUILD}"
	grep -Eq '^SHA256="[0-9a-f]{64}"$' "${BUILD}"
	grep -q 'CONF="/etc/omadora/sddm-theme.conf"' "${BUILD}"
	grep -q 'Commons/Settings.conf' "${BUILD}"
}

@test "build: the Containerfile runs the script" {
	grep -q '/ctx/build/32-sddm-theme.sh' "${ROOT}/Containerfile"
}
