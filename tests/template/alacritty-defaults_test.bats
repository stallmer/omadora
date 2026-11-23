#!/usr/bin/env bats
# Static checks for the Alacritty defaults the image ships in /etc/alacritty.
#
# Run with: bats tests/template/alacritty-defaults_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
FILES="${SCRIPT_DIR}/../../custom/files"

@test "alacritty-defaults: the system config and both examples are valid TOML" {
	command -v python3 >/dev/null || skip "python3 is not installed"
	for f in etc/alacritty/alacritty.toml usr/share/omadora/examples/alacritty.toml usr/share/omadora/skel/.config/noctalia/omadora.toml; do
		run python3 -I -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "${FILES}/${f}"
		[ "$status" -eq 0 ]
	done
}

@test "alacritty-defaults: the theme import has a seeded placeholder" {
	grep -qF '~/.config/alacritty/themes/noctalia.toml' "${FILES}/etc/alacritty/alacritty.toml"
	[ -f "${FILES}/usr/share/omadora/skel/.config/alacritty/themes/noctalia.toml" ]
}

@test "alacritty-defaults: the example keeps the system defaults with an import" {
	grep -qF 'import = ["/etc/alacritty/alacritty.toml"]' "${FILES}/usr/share/omadora/examples/alacritty.toml"
}

@test "alacritty-defaults: the real alacritty accepts the system config" {
	command -v alacritty >/dev/null || skip "alacritty is not installed"
	home="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/alacritty-home.$$"
	mkdir -p "${home}"
	cp -rT "${FILES}/usr/share/omadora/skel" "${home}"
	HOME="${home}" XDG_CONFIG_HOME="${home}/.config" run alacritty migrate --dry-run -c "${FILES}/etc/alacritty/alacritty.toml"
	[ "$status" -eq 0 ]
	# It followed the import into the seeded placeholder.
	[[ "$output" == *"themes/noctalia.toml"* ]]
	[[ "$output" != *"rror"* ]]
}
