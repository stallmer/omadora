#!/usr/bin/env bats
# Unit tests for custom/files/usr/bin/omadora-setup.
#
# chezmoi is stubbed on PATH and logs its arguments. HOME and XDG_DATA_HOME
# point into a sandbox, so nothing touches the host.
#
# Run with: bats tests/template/omadora-setup_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
SETUP_SRC="${SCRIPT_DIR}/../../custom/files/usr/bin/omadora-setup"

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
	export CHEZMOI_LOG
	unset OMADORA_DOTFILES_REPO
}

@test "omadora-setup: the first run clones and applies the default repository" {
	run "${SETUP_SRC}"
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "init --apply https://github.com/stallmer/omadora-dotfiles.git" ]
}

@test "omadora-setup: the repository can be overridden from the environment" {
	OMADORA_DOTFILES_REPO="https://example.invalid/me/dots.git" run "${SETUP_SRC}"
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "init --apply https://example.invalid/me/dots.git" ]
}

@test "omadora-setup: a later run updates instead of cloning again" {
	mkdir -p "${XDG_DATA_HOME}/chezmoi/.git"
	run "${SETUP_SRC}"
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "update" ]
}

@test "omadora-setup: --force is passed through on the first run and on updates" {
	run "${SETUP_SRC}" --force
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "init --apply --force https://github.com/stallmer/omadora-dotfiles.git" ]

	mkdir -p "${XDG_DATA_HOME}/chezmoi/.git"
	: >"${CHEZMOI_LOG}"
	run "${SETUP_SRC}" --force
	[ "$status" -eq 0 ]
	[ "$(cat "${CHEZMOI_LOG}")" = "update --force" ]
}

@test "omadora-setup: an unknown argument exits 2 with the usage line and runs nothing" {
	run "${SETUP_SRC}" --bogus
	[ "$status" -eq 2 ]
	[[ "$output" == *"usage: omadora-setup [--force]"* ]]
	[ ! -e "${CHEZMOI_LOG}" ]
}

@test "omadora-setup: --help prints the usage comment and runs nothing" {
	run "${SETUP_SRC}" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"omadora-setup --force"* ]]
	[ ! -e "${CHEZMOI_LOG}" ]
}

@test "omadora-setup: a failing chezmoi makes the script fail, so the hook retries" {
	cat >"${STUB_BIN}/chezmoi" <<'STUB'
#!/usr/bin/bash
exit 1
STUB
	run "${SETUP_SRC}"
	[ "$status" -ne 0 ]
}
