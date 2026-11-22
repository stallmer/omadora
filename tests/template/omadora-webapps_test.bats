#!/usr/bin/env bats
# Tests for the web app commands: omadora-launch-webapp, omadora-webapp-install and
# omadora-webapp-remove, plus the default list the first-login hook installs.
#
# flatpak, curl, niri and update-desktop-database are stubbed on PATH (jq is the
# real one). HOME and XDG_DATA_HOME point into a sandbox.
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
	# curl: writes the -o target based on the URL. A *.png or /static/ URL gets a PNG,
	# except /apple-touch-icon.png when CURL_SPA is set (a single-page app that
	# answers every path with HTML, like Fastmail). Any other URL gets the page in
	# CURL_PAGE, or HTML. CURL_BODY=html makes every answer HTML; CURL_FAIL fails.
	cat >"${STUB_BIN}/curl" <<'STUB'
#!/usr/bin/bash
printf 'curl %s\n' "$*" >> "${CALL_LOG}"
[ -n "${CURL_FAIL:-}" ] && exit 22
dest=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) dest="$2"; shift ;;
    http*) url="$1" ;;
  esac
  shift
done
png() { printf '\x89PNG\r\n\x1a\n....' > "${dest}"; }
html() { printf '<html>not an image</html>' > "${dest}"; }
if [ "${CURL_BODY:-}" = "html" ]; then html; exit 0; fi
case "${url}" in
  */apple-touch-icon.png) if [ -n "${CURL_SPA:-}" ]; then html; else png; fi ;;
  */static/* | *.png) png ;;
  *) if [ -n "${CURL_PAGE:-}" ]; then cat "${CURL_PAGE}" > "${dest}"; else html; fi ;;
esac
STUB
	# niri: `msg --json windows` prints NIRI_WINDOWS (a file); other calls are logged.
	# NIRI_FAIL makes it fail, as when no compositor is running.
	cat >"${STUB_BIN}/niri" <<'STUB'
#!/usr/bin/bash
printf 'niri %s\n' "$*" >> "${CALL_LOG}"
[ -n "${NIRI_FAIL:-}" ] && exit 1
if [ "$1 $2 $3" = "msg --json windows" ]; then cat "${NIRI_WINDOWS:-/dev/null}"; fi
exit 0
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
	unset FLATPAK_MISSING CURL_FAIL CURL_BODY CURL_SPA CURL_PAGE NIRI_FAIL NIRI_WINDOWS
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

# A windows list as `niri msg --json windows` prints it.
windows_json() {
	printf '[{"id": 4, "app_id": "%s", "title": "x"}, {"id": 9, "app_id": "org.gnome.Nautilus", "title": "y"}]' "$1" >"${TEST_ROOT}/windows.json"
	export NIRI_WINDOWS="${TEST_ROOT}/windows.json"
}

@test "launch: an open window for the site is focused instead of launching another" {
	windows_json "chrome-app.fastmail.com__mail_Inbox_-Default"
	run "${LAUNCH}" "https://app.fastmail.com/mail/Inbox/"
	[ "$status" -eq 0 ]
	grep -qx 'niri msg action focus-window --id 4' "${CALL_LOG}"
	run grep -c 'flatpak run' "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "launch: no window for the site means a new one is launched" {
	windows_json "chrome-other.example.com__-Default"
	run "${LAUNCH}" "https://app.fastmail.com/mail/Inbox/"
	[ "$status" -eq 0 ]
	grep -qx 'flatpak run org.chromium.Chromium --app=https://app.fastmail.com/mail/Inbox/' "${CALL_LOG}"
	run grep -c 'focus-window' "${CALL_LOG}"
	[ "$output" = "0" ]
}

@test "launch: it still launches when niri is not available" {
	NIRI_FAIL=1 run "${LAUNCH}" "https://app.fastmail.com/mail/Inbox/"
	[ "$status" -eq 0 ]
	grep -qx 'flatpak run org.chromium.Chromium --app=https://app.fastmail.com/mail/Inbox/' "${CALL_LOG}"
}

@test "launch: the window id follows Chromium's naming for each url shape" {
	# url -> the app id Chromium gives the window.
	check() {
		windows_json "$2"
		: >"${CALL_LOG}"
		run "${LAUNCH}" "$1"
		[ "$status" -eq 0 ]
		grep -qx 'niri msg action focus-window --id 4' "${CALL_LOG}"
	}
	check "https://example.com/" "chrome-example.com__-Default"
	check "https://example.com" "chrome-example.com__-Default"
	check "https://example.com/a/b" "chrome-example.com__a_b-Default"
	check "https://example.com/a/b/?x=1#frag" "chrome-example.com__a_b_-Default"
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

write_page() {
	cat >"${TEST_ROOT}/page.html" <<'HTML'
<html><head>
<link rel="apple-touch-icon" sizes="180x180" href="/static/favicons/FM-App-Icon-180.png">
<link rel="shortcut icon" sizes="192x192" href="/static/favicons/FM-App-Icon-192.png">
<link rel="shortcut icon" sizes="512x512" href="/static/favicons/FM-App-Icon-512.png">
<link id="favicon" rel="shortcut icon" sizes="32x32" href="/static/favicons/icon-32x32.png">
</head><body></body></html>
HTML
	export CURL_PAGE="${TEST_ROOT}/page.html"
}

@test "install: it uses the largest PNG the page declares, even when /apple-touch-icon.png is HTML" {
	write_page
	CURL_SPA=1 run "${INSTALL}" Fastmail "https://app.fastmail.com/mail/Inbox/"
	[ "$status" -eq 0 ]
	grep -qF 'https://app.fastmail.com/static/favicons/FM-App-Icon-512.png' "${CALL_LOG}"
	run grep -c 'apple-touch-icon.png' "${CALL_LOG}"
	[ "$output" = "0" ]
	grep -qx "Icon=${XDG_DATA_HOME}/omadora/webapps/icons/fastmail.png" "${DESKTOP}"
}

@test "install: relative, root-relative and protocol-relative icon links all resolve" {
	cat >"${TEST_ROOT}/page.html" <<'HTML'
<link rel="icon" sizes="64x64" href="icons/a.png">
HTML
	export CURL_PAGE="${TEST_ROOT}/page.html"
	CURL_SPA=1 run "${INSTALL}" One "https://example.com/app/index.html"
	grep -qF 'https://example.com/app/icons/a.png' "${CALL_LOG}"

	printf '<link rel="icon" href="//cdn.example.com/b.png">' >"${TEST_ROOT}/page.html"
	: >"${CALL_LOG}"
	CURL_SPA=1 run "${INSTALL}" Two "https://example.com/x/"
	grep -qF 'https://cdn.example.com/b.png' "${CALL_LOG}"

	printf '<link rel="icon" href="/c.png">' >"${TEST_ROOT}/page.html"
	: >"${CALL_LOG}"
	CURL_SPA=1 run "${INSTALL}" Three "https://example.com/x/y/"
	grep -qF 'https://example.com/c.png' "${CALL_LOG}"
}

@test "install: a page with only non-PNG icon links falls back to the generic icon" {
	printf '<link rel="icon" type="image/svg+xml" href="/icon.svg">\n<link rel="shortcut icon" href="/favicon.ico">' >"${TEST_ROOT}/page.html"
	export CURL_PAGE="${TEST_ROOT}/page.html"
	CURL_SPA=1 run "${INSTALL}" Fastmail "https://app.fastmail.com/"
	[ "$status" -eq 0 ]
	grep -qx 'Icon=web-browser' "${DESKTOP}"
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
