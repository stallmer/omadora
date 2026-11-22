#!/usr/bin/env bats
# Static checks for the Niri keybindings the image ships.
#
# niri itself validates the full config during the image build
# (build/30-desktop.sh runs `niri validate`); these tests catch the common
# mistakes earlier and without niri installed.
#
# Run with: bats tests/template/niri-binds_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
BINDS="${SCRIPT_DIR}/../../custom/files/etc/niri/omadora-binds.kdl"
DESKTOP="${SCRIPT_DIR}/../../build/30-desktop.sh"

# The key of every bind line: the first token inside the binds block.
bind_keys() {
	grep -E '^[[:space:]]+(Mod|Alt|Ctrl|Shift|Super|[A-Z][A-Za-z0-9_]*)[A-Za-z0-9_+]*[[:space:]]' "${BINDS}" |
		grep -v '^[[:space:]]*//' | awk '{print $1}'
}

@test "niri-binds: the binds file exists and defines a binds block" {
	[ -f "${BINDS}" ]
	grep -qx 'binds {' "${BINDS}"
}

@test "niri-binds: no key is defined twice (niri rejects duplicates in one file)" {
	run bash -c "$(declare -f bind_keys); BINDS='${BINDS}'; bind_keys | sort | uniq -d"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "niri-binds: every bind has a hotkey-overlay title" {
	total="$(bind_keys | wc -l)"
	titled="$(grep -c 'hotkey-overlay-title=' "${BINDS}")"
	[ "${total}" -gt 0 ]
	[ "${total}" -eq "${titled}" ]
}

@test "niri-binds: Alt+Tab is left to niri's own window switcher" {
	run bash -c "$(declare -f bind_keys); BINDS='${BINDS}'; bind_keys | grep -c -x -E 'Alt\\+(Shift\\+)?Tab'"
	[ "$output" = "0" ]
}

@test "niri-binds: the desktop script includes the file and validates the final config" {
	grep -qF 'include "omadora-binds.kdl"' "${DESKTOP}"
	grep -qF 'niri validate -c /etc/niri/config.kdl' "${DESKTOP}"
}
