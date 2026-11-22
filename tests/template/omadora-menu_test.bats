#!/usr/bin/env bats
# Tests for the Omadora menu, a Noctalia launcher plugin shipped in the image:
# the plugin's logic (under the standalone Luau interpreter) and the wiring that
# enables it.
#
# Run with: bats tests/template/omadora-menu_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO="${SCRIPT_DIR}/../.."
PLUGIN="${REPO}/custom/files/usr/share/omadora/plugins/menu"
DEFAULTS="${REPO}/custom/files/etc/xdg/noctalia/10-omadora.toml"
BINDS="${REPO}/custom/files/etc/niri/omadora-binds.kdl"

@test "omadora-menu: the logic tests pass under luau" {
	if ! command -v luau >/dev/null 2>&1; then
		# CI installs luau, so a missing interpreter there is a real failure.
		[ -z "${CI:-}" ] || { echo "luau is not installed but CI is set" >&2; return 1; }
		skip "luau is not installed"
	fi
	cd "${REPO}"
	run luau tests/luau/menu_test.luau
	[ "$status" -eq 0 ]
	[[ "$output" == *"all menu checks passed"* ]]
}

@test "omadora-menu: the manifest declares the plugin id and the om launcher prefix" {
	grep -qx 'id = "omadora/menu"' "${PLUGIN}/plugin.toml"
	grep -qx 'prefix = "om"' "${PLUGIN}/plugin.toml"
	grep -qx '\[\[launcher_provider\]\]' "${PLUGIN}/plugin.toml"
	grep -qx 'entry = "menu.luau"' "${PLUGIN}/plugin.toml"
	[ -f "${PLUGIN}/menu.luau" ]
	[ -f "${PLUGIN}/tree.luau" ]
}

@test "omadora-menu: plugin_api is at least 24, which the argv form of runAsync needs" {
	level="$(grep -E '^plugin_api = ' "${PLUGIN}/plugin.toml" | sed -E 's/^plugin_api = ([0-9]+).*/\1/')"
	[ "${level}" -ge 24 ]
	# Noctalia 5.4.1, the version in Fedora 44, supports up to level 34.
	[ "${level}" -le 34 ]
}

@test "omadora-menu: the shipped Noctalia defaults enable the plugin from the image's plugin directory" {
	grep -qx 'enabled = \["omadora/menu"\]' "${DEFAULTS}"
	grep -qx 'kind = "path"' "${DEFAULTS}"
	grep -qx 'location = "/usr/share/omadora/plugins"' "${DEFAULTS}"
}

@test "omadora-menu: Super+Alt+Space opens the launcher on the om prefix" {
	grep -F 'Mod+Alt+Space' "${BINDS}" | grep -qF '"/om "'
}

@test "omadora-menu: the entry script only uses documented plugin globals" {
	# Anything else would fail at runtime inside Noctalia, where the tests cannot reach.
	run grep -oE '(noctalia|launcher)\.[A-Za-z]+' "${PLUGIN}/menu.luau"
	[ "$status" -eq 0 ]
	for call in $(printf '%s\n' "${output}" | sort -u); do
		case "${call}" in
			noctalia.fuzzyScore | noctalia.runAsync | noctalia.runInTerminal | launcher.setResults | launcher.setQuery) ;;
			*) echo "unexpected API call: ${call}" >&2; return 1 ;;
		esac
	done
}
