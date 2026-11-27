#!/usr/bin/env bats
# Unit tests for custom/files/usr/bin/omadora-theme-set.
#
# noctalia is stubbed on PATH and logs its arguments.
#
# Run with: bats tests/template/omadora-theme-set_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
THEME_SRC="${SCRIPT_DIR}/../../custom/files/usr/bin/omadora-theme-set"
NOCTALIA_TOML="${SCRIPT_DIR}/../../custom/files/etc/xdg/noctalia/10-omadora.toml"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/omadora-theme-set.${BATS_TEST_NUMBER:-0}.$$"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	CALL_LOG="${TEST_ROOT}/noctalia.log"
	mkdir -p "${STUB_BIN}"
	cat >"${STUB_BIN}/noctalia" <<'STUB'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${CALL_LOG}"
STUB
	chmod +x "${STUB_BIN}/noctalia"
	# pkexec is stubbed too, so a test never runs the real privileged helper.
	cat >"${STUB_BIN}/pkexec" <<'STUB'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${PKEXEC_LOG}"
exit "${PKEXEC_STATUS:-0}"
STUB
	chmod +x "${STUB_BIN}/pkexec"
	export PATH="${STUB_BIN}:${PATH}"
	PKEXEC_LOG="${TEST_ROOT}/pkexec.log"
	export CALL_LOG PKEXEC_LOG
}

@test "omadora-theme-set: a theme name switches to that bundled palette" {
	run "${THEME_SRC}" Gruvbox
	[ "$status" -eq 0 ]
	[ "$(cat "${CALL_LOG}")" = "msg color-scheme-set builtin Gruvbox" ]
}

@test "omadora-theme-set: case, spaces and hyphens are ignored" {
	run "${THEME_SRC}" "tokyo night"
	[ "$status" -eq 0 ]
	[ "$(cat "${CALL_LOG}")" = "msg color-scheme-set builtin Tokyo-Night" ]
}

@test "omadora-theme-set: an unaccented name matches Rosé Pine" {
	run "${THEME_SRC}" rosepine
	[ "$status" -eq 0 ]
	[ "$(cat "${CALL_LOG}")" = "msg color-scheme-set builtin Rosé Pine" ]
}

@test "omadora-theme-set: an unknown theme exits 2, lists the themes and runs nothing" {
	run "${THEME_SRC}" bogus
	[ "$status" -eq 2 ]
	[[ "$output" == *"unknown theme 'bogus'"* ]]
	[[ "$output" == *"Tokyo-Night"* ]]
	[ ! -e "${CALL_LOG}" ]
}

@test "omadora-theme-set: --list prints the ten bundled themes and runs nothing" {
	run "${THEME_SRC}" --list
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 10 ]
	[[ "$output" == *"Catppuccin"* ]]
	[ ! -e "${CALL_LOG}" ]
}

@test "omadora-theme-set: no argument shows the current theme and mode" {
	run "${THEME_SRC}"
	[ "$status" -eq 0 ]
	mapfile -t calls <"${CALL_LOG}"
	[ "${calls[0]}" = "msg color-scheme-get" ]
	[ "${calls[1]}" = "msg theme-mode-get" ]
}

@test "omadora-theme-set: --mode passes dark, light and auto through" {
	for mode in dark light auto; do
		: >"${CALL_LOG}"
		run "${THEME_SRC}" --mode "${mode}"
		[ "$status" -eq 0 ]
		[ "$(cat "${CALL_LOG}")" = "msg theme-mode-set ${mode}" ]
	done
}

@test "omadora-theme-set: a bad or missing mode exits 2 and runs nothing" {
	run "${THEME_SRC}" --mode purple
	[ "$status" -eq 2 ]
	run "${THEME_SRC}" --mode
	[ "$status" -eq 2 ]
	[ ! -e "${CALL_LOG}" ]
}

@test "omadora-theme-set: an unknown option exits 2 and runs nothing" {
	run "${THEME_SRC}" --bogus
	[ "$status" -eq 2 ]
	[ ! -e "${CALL_LOG}" ]
}

@test "omadora-theme-set: --help prints the usage comment and runs nothing" {
	run "${THEME_SRC}" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"omadora-theme-set --list"* ]]
	[ ! -e "${CALL_LOG}" ]
}

@test "omadora-theme-set: the shipped default theme is one of the listed themes" {
	default="$(grep -E '^builtin = ' "${NOCTALIA_TOML}" | sed -E 's/^builtin = "(.*)"$/\1/')"
	run "${THEME_SRC}" --list
	[[ "$output" == *"${default}"* ]]
}

@test "omadora-theme-set: a theme name also updates the login screen theme" {
	run "${THEME_SRC}" Gruvbox
	[ "$status" -eq 0 ]
	[ "$(cat "${PKEXEC_LOG}")" = "/usr/libexec/omadora-sddm-theme scheme Gruvbox" ]
}

@test "omadora-theme-set: Rosé Pine and Noctalia use the login theme's own names" {
	run "${THEME_SRC}" rosepine
	[ "$status" -eq 0 ]
	run "${THEME_SRC}" noctalia
	[ "$status" -eq 0 ]
	[ "$(sed -n 1p "${PKEXEC_LOG}")" = "/usr/libexec/omadora-sddm-theme scheme Rosepine" ]
	[ "$(sed -n 2p "${PKEXEC_LOG}")" = "/usr/libexec/omadora-sddm-theme scheme Noctalia-default" ]
}

@test "omadora-theme-set: --mode updates the login screen, and auto becomes dark" {
	run "${THEME_SRC}" --mode light
	[ "$status" -eq 0 ]
	run "${THEME_SRC}" --mode auto
	[ "$status" -eq 0 ]
	[ "$(sed -n 1p "${PKEXEC_LOG}")" = "/usr/libexec/omadora-sddm-theme mode light" ]
	[ "$(sed -n 2p "${PKEXEC_LOG}")" = "/usr/libexec/omadora-sddm-theme mode dark" ]
	[ "$(sed -n 2p "${CALL_LOG}")" = "msg theme-mode-set auto" ]
}

@test "omadora-theme-set: a login screen failure warns but keeps the Noctalia change" {
	PKEXEC_STATUS=126 run "${THEME_SRC}" Nord
	[ "$status" -eq 0 ]
	[[ "$output" == *"could not update the login screen theme"* ]]
	[ "$(cat "${CALL_LOG}")" = "msg color-scheme-set builtin Nord" ]
}

@test "omadora-theme-set: an unknown theme and --list never touch the login screen" {
	run "${THEME_SRC}" bogus
	[ "$status" -eq 2 ]
	run "${THEME_SRC}" --list
	[ "$status" -eq 0 ]
	[ ! -e "${PKEXEC_LOG}" ]
}
