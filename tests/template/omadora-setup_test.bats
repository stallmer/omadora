#!/usr/bin/env bats
# Unit tests for custom/files/usr/bin/omadora-setup.
#
# chezmoi is stubbed on PATH and logs its arguments. HOME and XDG_DATA_HOME
# point into a sandbox, so nothing touches the host.
#
# Run with: bats tests/template/omadora-setup_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
SETUP_SRC="${SCRIPT_DIR}/../../custom/files/usr/bin/omadora-setup"
SKEL_SRC="${SCRIPT_DIR}/../../custom/files/usr/share/omadora/skel"
HOOK_SRC="${SCRIPT_DIR}/../../custom/files/usr/share/ublue-os/user-setup.hooks.d/30-omadora-skel.sh"

setup() {
	TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/omadora-setup.${BATS_TEST_NUMBER:-0}.$$"
	STUB_BIN="${TEST_ROOT}/stub-bin"
	CHEZMOI_LOG="${TEST_ROOT}/chezmoi.log"
	mkdir -p "${STUB_BIN}" "${TEST_ROOT}/home"

	cat >"${STUB_BIN}/chezmoi" <<'STUB'
#!/usr/bin/bash
printf '%s\n' "$*" >> "${CHEZMOI_LOG}"
STUB
	chmod +x "${STUB_BIN}/chezmoi"

	export PATH="${STUB_BIN}:${PATH}"
	export HOME="${TEST_ROOT}/home"
	export XDG_DATA_HOME="${HOME}/.local/share"
	export OMADORA_SKEL="${SKEL_SRC}"
	export CHEZMOI_LOG
}

# A chezmoi source directory that is a git repository with an origin.
make_source() {
	mkdir -p "${XDG_DATA_HOME}/chezmoi"
	git -C "${XDG_DATA_HOME}/chezmoi" init -q
	git -C "${XDG_DATA_HOME}/chezmoi" remote add origin "$1"
}

@test "omadora-setup --skel: copies the default files into an empty home" {
	run "${SETUP_SRC}" --skel
	[ "$status" -eq 0 ]
	[ -f "${HOME}/.config/niri/noctalia.kdl" ]
	[ -f "${HOME}/.config/alacritty/themes/noctalia.toml" ]
	[ -f "${HOME}/.config/noctalia/omadora.toml" ]
	[ ! -e "${CHEZMOI_LOG}" ]
}

@test "omadora-setup --skel: never overwrites a file the user already has" {
	mkdir -p "${HOME}/.config/noctalia"
	echo "mine" >"${HOME}/.config/noctalia/omadora.toml"
	run "${SETUP_SRC}" --skel
	[ "$status" -eq 0 ]
	[ "$(cat "${HOME}/.config/noctalia/omadora.toml")" = "mine" ]
	[ -f "${HOME}/.config/niri/noctalia.kdl" ]
}

@test "omadora-setup --skel: running it twice changes nothing" {
	run "${SETUP_SRC}" --skel
	echo "themed" >"${HOME}/.config/niri/noctalia.kdl"
	run "${SETUP_SRC}" --skel
	[ "$status" -eq 0 ]
	[ "$(cat "${HOME}/.config/niri/noctalia.kdl")" = "themed" ]
}

@test "omadora-setup --skel: a missing skeleton directory is an error, so the hook retries" {
	OMADORA_SKEL="${TEST_ROOT}/nope" run "${SETUP_SRC}" --skel
	[ "$status" -ne 0 ]
}

@test "omadora-setup <repo>: initializes and applies that repository" {
	run "${SETUP_SRC}" git@github.com:someone/dotfiles.git
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "init --apply git@github.com:someone/dotfiles.git" ]
}

@test "omadora-setup <repo>: --force is passed through, in either order" {
	run "${SETUP_SRC}" --force https://example.invalid/me/dots.git
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "init --apply --force https://example.invalid/me/dots.git" ]
	: >"${CHEZMOI_LOG}"
	run "${SETUP_SRC}" https://example.invalid/me/dots.git --force
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "init --apply --force https://example.invalid/me/dots.git" ]
}

@test "omadora-setup <repo>: refuses when a dotfiles repository is already set, and names it" {
	make_source "https://example.invalid/old/dots.git"
	run "${SETUP_SRC}" https://example.invalid/new/dots.git
	[ "$status" -eq 1 ]
	[[ "$output" == *"https://example.invalid/old/dots.git"* ]]
	[ ! -e "${CHEZMOI_LOG}" ]
}

@test "omadora-setup --update: pulls and applies the user's repository" {
	make_source "https://example.invalid/me/dots.git"
	run "${SETUP_SRC}" --update
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "update" ]
}

@test "omadora-setup --update: --force is passed through" {
	make_source "https://example.invalid/me/dots.git"
	run "${SETUP_SRC}" --update --force
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "update --force" ]
}

@test "omadora-setup --update: with no repository set it succeeds, says so and runs nothing" {
	run "${SETUP_SRC}" --update
	[ "$status" -eq 0 ]
	[[ "$output" == *"no dotfiles repository is set"* ]]
	[ ! -e "${CHEZMOI_LOG}" ]
}

@test "omadora-setup: no argument, an unknown option or two modes exit 2 with the usage line and run nothing" {
	run "${SETUP_SRC}"
	[ "$status" -eq 2 ]
	[[ "$output" == *"usage: omadora-setup"* ]]
	run "${SETUP_SRC}" --bogus
	[ "$status" -eq 2 ]
	run "${SETUP_SRC}" --skel --update
	[ "$status" -eq 2 ]
	run "${SETUP_SRC}" --update https://example.invalid/me/dots.git
	[ "$status" -eq 2 ]
	[ ! -e "${CHEZMOI_LOG}" ]
}

@test "omadora-setup: --help prints the usage comment and runs nothing" {
	run "${SETUP_SRC}" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"omadora-setup --skel"* ]]
	[ ! -e "${CHEZMOI_LOG}" ]
}

@test "omadora-setup: a failing chezmoi makes the script fail" {
	make_source "https://example.invalid/me/dots.git"
	cat >"${STUB_BIN}/chezmoi" <<'STUB'
#!/usr/bin/bash
exit 1
STUB
	run "${SETUP_SRC}" --update
	[ "$status" -ne 0 ]
}

@test "skeleton hook: runs omadora-setup --skel once, under its own version key" {
	grep -qF 'version-script-check omadora-skel user 1' "${HOOK_SRC}"
	grep -qF '/usr/bin/omadora-setup --skel' "${HOOK_SRC}"
	grep -qF 'version-script-commit omadora-skel user 1' "${HOOK_SRC}"
	[ ! -e "${SCRIPT_DIR}/../../custom/files/usr/share/ublue-os/user-setup.hooks.d/30-omadora-dotfiles.sh" ]
}
