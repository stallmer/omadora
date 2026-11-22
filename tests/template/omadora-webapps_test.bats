#!/usr/bin/env bats
# Tests for the web app commands: omadora-launch-webapp, omadora-webapp-install and
# omadora-webapp-remove, plus the default list the first-login hook installs.
#
# flatpak, curl and update-desktop-database are stubbed on PATH. HOME and
# XDG_DATA_HOME point into a sandbox.
#
# Run with: bats tests/template/omadora-webapps_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO="${SCRIPT_DIR}/../.."
LAUNCH="${REPO}/custom/files/usr/bin/omadora-launch-webapp"
INSTALL="${REPO}/custom/files/usr/bin/omadora-webapp-install"
REMOVE="${REPO}/custom/files/usr/bin/omadora-webapp-remove"
DEFAULTS="${REPO}/custom/files/usr/share/omadora/default-webapps"
HOOK="${REPO}/custom/files/usr/share/ublue-os/user-setup.hooks.d/40-omadora-webapps.sh"
BINDS="${REPO}/custom/files/etc/niri/omadora-binds.kdl"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/webapps.${BATS_TEST_NUMBER:-0}.$$"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	CALL_LOG="${TEST_ROOT}/calls.log"
	mkdir -p "${STUB_BIN}" "${TEST_ROOT}/home"

	# flatpak: `info` succeeds unless FLATPAK_MISSING is set; `run` just logs.
	cat >"${STUB_BIN}/flatpak" <<'STUB'
#!/usr/bin/bash
printf 'flatpak %s\n' "$*" >> "${CALL_LOG}"
if [ "$1" = "info" ] && [ -n "${FLATPAK_MISSING:-}" ]; then exit 1; fi
exit 0
STUB
	# curl: writes a PNG (or HTML when CURL_BODY=html) to the -o target, or fails.
	cat >"${STUB_BIN}/curl" <<'STUB'
#!/usr/bin/bash
printf 'curl %s\n' "$*" >> "${CALL_LOG}"
[ -n "${CURL_FAIL:-}" ] && exit 22
dest=""
while [ $# -gt 0 ]; do
  [ "$1" = "-o" ] && dest="$2"
  shift
done
if [ "${CURL_BODY:-png}" = "html" ]; then
  printf '<html>not an image</html>' > "${dest}"
else
  printf '\x89PNG\r\n\x1a\n....' > "${dest}"
fi
STUB
	cat >"${STUB_BIN}/update-desktop-database" <<'STUB'
#!/usr/bin/bash
printf 'update-desktop-database %s\n' "$*" >> "${CALL_LOG}"
STUB
	chmod +x "${STUB_BIN}"/*

	export PATH="${STUB_BIN}:${PATH}"
	export HOME="${TEST_ROOT}/home"
	export XDG_DATA_HOME="${HOME}/.local/share"
	export CALL_LOG
	unset FLATPAK_MISSING CURL_FAIL CURL_BODY
	DESKTOP="${XDG_DATA_HOME}/applications/omadora-webapp-fastmail.desktop"
}

# --- omadora-launch-webapp -------------------------------------------------

@test "launch: opens the url in Chromium's app mode" {
	run "${LAUNCH}" "https://app.fastmail.com/mail/Inbox/"
	[ "$status" -eq 0 ]
	grep -qx 'flatpak run org.chromium.Chromium --app=https://app.fastmail.com/mail/Inbox/' "${CALL_LOG}"
}

@test "launch: a missing or non-http url exits 2 and runs nothing" {
	run "${LAUNCH}"
	[ "$status" -eq 2 ]
	run "${LAUNCH}" "ftp://example.com"
	[ "$status" -eq 2 ]
	[ ! -e "${CALL_LOG}" ]
}

@test "launch: without the Chromium Flatpak it explains and exits 1" {
	FLATPAK_MISSING=1 run "${LAUNCH}" "https://example.com"
	[ "$status" -eq 1 ]
	[[ "$output" == *"not installed yet"* ]]
	run grep -c 'flatpak run' "${CALL_LOG}"
	[ "$output" = "0" ]
}

# --- omadora-webapp-install ------------------------------------------------

@test "install: writes a desktop entry that launches the url" {
	run "${INSTALL}" Fastmail "https://app.fastmail.com/mail/Inbox/"
	[ "$status" -eq 0 ]
	grep -qx 'Name=Fastmail' "${DESKTOP}"
	grep -qx 'Exec=omadora-launch-webapp "https://app.fastmail.com/mail/Inbox/"' "${DESKTOP}"
	grep -qx 'X-Omadora-Webapp=true' "${DESKTOP}"
	grep -qx 'Type=Application' "${DESKTOP}"
	grep -qx 'Terminal=false' "${DESKTOP}"
}

@test "install: the file name is a slug of the name" {
	run "${INSTALL}" "My Cool App!" "https://example.com"
	[ "$status" -eq 0 ]
	[ -f "${XDG_DATA_HOME}/applications/omadora-webapp-my-cool-app.desktop" ]
	grep -qx 'Name=My Cool App!' "${XDG_DATA_HOME}/applications/omadora-webapp-my-cool-app.desktop"
}

@test "install: with no icon argument it uses the site's own apple-touch-icon" {
	run "${INSTALL}" Fastmail "https://app.fastmail.com/mail/Inbox/"
	[ "$status" -eq 0 ]
	grep -qF 'https://app.fastmail.com/apple-touch-icon.png' "${CALL_LOG}"
	grep -qx "Icon=${XDG_DATA_HOME}/omadora/webapps/icons/fastmail.png" "${DESKTOP}"
	[ -f "${XDG_DATA_HOME}/omadora/webapps/icons/fastmail.png" ]
}

@test "install: if the site icon cannot be fetched it falls back to a generic icon" {
	CURL_FAIL=1 run "${INSTALL}" Fastmail "https://app.fastmail.com/"
	[ "$status" -eq 0 ]
	grep -qx 'Icon=web-browser' "${DESKTOP}"
}

@test "install: a response that is not a PNG is ignored" {
	CURL_BODY=html run "${INSTALL}" Fastmail "https://app.fastmail.com/"
	[ "$status" -eq 0 ]
	grep -qx 'Icon=web-browser' "${DESKTOP}"
	[ ! -e "${XDG_DATA_HOME}/omadora/webapps/icons/fastmail.png" ]
}

@test "install: an icon file given by the caller is copied and used" {
	printf '<svg/>' >"${TEST_ROOT}/mine.svg"
	run "${INSTALL}" Fastmail "https://app.fastmail.com/" "${TEST_ROOT}/mine.svg"
	[ "$status" -eq 0 ]
	grep -qx "Icon=${XDG_DATA_HOME}/omadora/webapps/icons/fastmail.svg" "${DESKTOP}"
	[ -f "${XDG_DATA_HOME}/omadora/webapps/icons/fastmail.svg" ]
	run grep -c apple-touch-icon "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "install: an icon with another extension is rejected" {
	run "${INSTALL}" Fastmail "https://app.fastmail.com/" "${TEST_ROOT}/icon.exe"
	[ "$status" -eq 2 ]
	[ ! -e "${DESKTOP}" ]
}

@test "install: unsafe or invalid urls are rejected" {
	for bad in 'ftp://example.com' 'example.com' 'https://exa mple.com' 'https://example.com/"x' 'https://example.com/$HOME' 'https://example.com/`id`' 'https://example.com/\x'; do
		run "${INSTALL}" Bad "${bad}"
		[ "$status" -eq 2 ]
	done
	[ ! -e "${XDG_DATA_HOME}/applications/omadora-webapp-bad.desktop" ]
}

@test "install: a percent sign in the url is doubled in the Exec line" {
	run "${INSTALL}" Spaced "https://example.com/a%20b"
	[ "$status" -eq 0 ]
	grep -qxF 'Exec=omadora-launch-webapp "https://example.com/a%%20b"' "${XDG_DATA_HOME}/applications/omadora-webapp-spaced.desktop"
}

@test "install: a missing name or url, or a name with no letters, is rejected" {
	run "${INSTALL}"
	[ "$status" -eq 2 ]
	run "${INSTALL}" Name
	[ "$status" -eq 2 ]
	run "${INSTALL}" "!!!" "https://example.com"
	[ "$status" -eq 2 ]
}

@test "install: running it twice updates the same single entry" {
	run "${INSTALL}" Fastmail "https://one.example.com/"
	run "${INSTALL}" Fastmail "https://two.example.com/"
	[ "$status" -eq 0 ]
	[ "$(ls "${XDG_DATA_HOME}/applications" | grep -c 'omadora-webapp-')" = "1" ]
	grep -qF 'two.example.com' "${DESKTOP}"
	run grep -c 'one.example.com' "${DESKTOP}"
	[ "$output" = "0" ]
}

# --- omadora-webapp-remove -------------------------------------------------

@test "remove: deletes the entry and its icon" {
	"${INSTALL}" Fastmail "https://app.fastmail.com/"
	[ -f "${DESKTOP}" ]
	run "${REMOVE}" Fastmail
	[ "$status" -eq 0 ]
	[ ! -e "${DESKTOP}" ]
	[ ! -e "${XDG_DATA_HOME}/omadora/webapps/icons/fastmail.png" ]
}

@test "remove: an unknown name exits 1" {
	run "${REMOVE}" nothing
	[ "$status" -eq 1 ]
	[[ "$output" == *"no web app named"* ]]
}

@test "remove: it leaves a file it did not create alone" {
	mkdir -p "${XDG_DATA_HOME}/applications"
	printf '[Desktop Entry]\nName=Mine\n' >"${DESKTOP}"
	run "${REMOVE}" Fastmail
	[ "$status" -eq 1 ]
	[ -f "${DESKTOP}" ]
}

@test "remove: a missing name exits 2" {
	run "${REMOVE}"
	[ "$status" -eq 2 ]
}

# --- the defaults and the first-login hook ----------------------------------

@test "defaults: every listed web app is name|http(s) url" {
	count=0
	while IFS='|' read -r name url; do
		[[ -z "${name}" || "${name}" == \#* ]] && continue
		[[ "${url}" == http://* || "${url}" == https://* ]]
		count=$((count + 1))
	done <"${DEFAULTS}"
	[ "${count}" -ge 1 ]
	grep -qx 'Fastmail|https://app.fastmail.com/mail/Inbox/' "${DEFAULTS}"
}

@test "hook: it uses the version check and commit, and installs from the default list" {
	grep -qF 'version-script-check omadora-webapps user 1' "${HOOK}"
	grep -qF 'version-script-commit omadora-webapps user 1' "${HOOK}"
	grep -qF '/usr/bin/omadora-webapp-install' "${HOOK}"
}

@test "binds: Super+Shift+E opens Fastmail and the bind has an overlay title" {
	grep -F 'Mod+Shift+E' "${BINDS}" | grep -qF 'omadora-launch-webapp'
	grep -F 'Mod+Shift+E' "${BINDS}" | grep -qF 'https://app.fastmail.com/mail/Inbox/'
	grep -F 'Mod+Shift+E' "${BINDS}" | grep -qF 'hotkey-overlay-title='
}
